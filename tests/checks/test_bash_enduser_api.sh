#!/bin/bash
# ==============================================================================
# Run the EndUser API examples added from the API reference against a stub
# curl, and check the calls they make: 03.Myself, 04.FileOperations,
# 05.Transfers, 06.ServerTime, and 02.Files 09 to 15.
#
# For each one: the method, the URL with its query, the body, the headers that
# matter (Content-MD5, Content-Range), the answers it acts on, and its exit
# code. The stub answers different URLs differently (STUB_CURL_GET_RULES), and
# a no-op sleep keeps the scripts that poll fast.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
EU_TREE="${REPO}/EndUser/API 2.0/bash"

WORK="${TESTS_DIR}/output/bash_enduser_api"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/eu" "${WORK}/files"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"

# The real EndUser set_variables.sh, with the test values as its local file, and
# a cookie jar, as 01.Authenticate/01.myself_POST.sh leaves it
cp "${EU_TREE}/set_variables.sh" "${WORK}/eu/set_variables.sh"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/eu/set_variables.local.sh"
for folder in 02.Files 03.Myself 04.FileOperations 05.Transfers 06.ServerTime; do
    cp -R "${EU_TREE}/${folder}" "${WORK}/eu/"
done
touch "${WORK}/eu/myCookie.jar"
BASE="https://st.example.com:8444/api/v2.0"

# body NAME JSON: a canned answer, in a file
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
# rules TEXT FILE [TEXT FILE...]: a STUB_CURL_GET_RULES file
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# run SCRIPT ARGS...: GET_BODY, RULES, POST_BODY, STATUS and STATUS_GET set the answers
run() {
    local rel="$1"; shift
    OUT=$(cd "${WORK}/eu/$(dirname "${rel}")" && PATH="${WORK}/bin:${PATH}" \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" \
          STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_STATUS="${STATUS:-200}" \
          STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE=1 \
          bash "./$(basename "${rel}")" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
headers() { printf '%s\n' "${OUT}" | sed -n 's/^HEADER: //p'; }

echo "=== Every new script needs the session, except the password reset ones ==="
mv "${WORK}/eu/myCookie.jar" "${WORK}/eu/myCookie.jar.off"
for rel in 03.Myself/01.myself_GET.sh 03.Myself/09.myself_addressBook_GET.sh 02.Files/09.files_GET_query.sh \
           04.FileOperations/05.fileOperations_id_DELETE.sh 05.Transfers/01.transfers_GET.sh 06.ServerTime/01.serverTime_GET.sh; do
    run "${rel}"
    expect "${rel}: stops before any call without a session" "${RC}:$(calls | wc -l | tr -d ' ')" "1:0"
done
mv "${WORK}/eu/myCookie.jar.off" "${WORK}/eu/myCookie.jar"

echo
echo "=== 03.Myself ==="
GET_BODY=$(body myself '{"name":"john","type":"user","contact":{"email":"john@example.com"},"sharingAllowed":true,"transfersWebServiceAllowed":true,"addressBookSettings":{"enabled":true},"messageOfTheDay":"Hello"}')
run 03.Myself/01.myself_GET.sh
expect "01 myself: GET /myself" "$(calls)" "GET ${BASE}/myself"
has "01 myself: prints the account in short" "account           john (user)"
has "01 myself: and whether sharing is allowed" "sharing allowed   true"

GET_BODY=$(body expired_no '{"message":"...","changePasswordURL":"https://x/api/v2.0/myself/password?operation=change","expired":false}')
run 03.Myself/02.myself_passwordExpired_GET.sh
expect "02 passwordExpired: not expired, exit 0" "${RC}:$(calls)" "0:GET ${BASE}/myself/passwordExpired"
GET_BODY=$(body expired_yes '{"message":"...","changePasswordURL":"https://x/api/v2.0/myself/password?operation=change","expired":true}')
run 03.Myself/02.myself_passwordExpired_GET.sh
expect "02 passwordExpired: expired, exit 2" "${RC}" "2"
has "02 passwordExpired: names the URL to change it at" "Change it at https://x/api/v2.0/myself/password?operation=change"
GET_BODY=

run 03.Myself/03.myself_password_POST_change.sh 'N3w p@ss'
expect "03 change: POSTs the change, then logs in again" "$(calls)" "POST ${BASE}/myself/password?operation=change
POST ${BASE}/myself"
expect "03 change: the operation is in the body too, with the old and new passwords" \
  "$(payload 1 | jq -c '[.operation, .oldPassword, .newPassword]')" '["change","s3cret","N3w p@ss"]'
has "03 change: logs in again with the new password" "BASIC_AUTH: apiadmin:N3w p@ss"
STATUS=400 run 03.Myself/03.myself_password_POST_change.sh 'N3w p@ss'
expect "03 change: refused, no new login, exit 1" "${RC}:$(calls | grep -c '/myself$')" "1:0"
run 03.Myself/03.myself_password_POST_change.sh
expect "03 change: needs NEW_PASSWORD" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

run 03.Myself/04.myself_password_POST_requestLink.sh john@example.com
expect "04 requestLink: POST with the operation in the query" "$(calls)" "POST ${BASE}/myself/password?operation=requestLink"
expect "04 requestLink: and in the body, with the email and username" \
  "$(payload 1 | jq -c '[.operation, .email, .username]')" '["requestLink","john@example.com","apiadmin"]'
expect "04 requestLink: sends no credentials and no session" "$(printf '%s\n' "${OUT}" | grep -c '^BASIC_AUTH:')" "0"

run 03.Myself/05.myself_password_POST_reset.sh tok-1 'N3w p@ss'
expect "05 reset: POST with the operation in the query" "$(calls)" "POST ${BASE}/myself/password?operation=reset"
expect "05 reset: token, new password, username; no secret answer when none is given" \
  "$(payload 1 | jq -c '[.operation, .token, .newPassword, .username, has("secretAnswer")]')" '["reset","tok-1","N3w p@ss","apiadmin",false]'
run 03.Myself/05.myself_password_POST_reset.sh tok-1 'N3w p@ss' 'blue' john
expect "05 reset: the secret answer and username, when given" "$(payload 1 | jq -c '[.secretAnswer, .username]')" '["blue","john"]'

GET_BODY=$(body questions '["Your first pet?","Your first school?"]')
run 03.Myself/06.secretQuestions_GET.sh
expect "06 secretQuestions: GET /secretQuestions" "$(calls)" "GET ${BASE}/secretQuestions"
has "06 secretQuestions: one question per line" "  Your first school?"
STATUS_GET=503 run 03.Myself/06.secretQuestions_GET.sh
expect "06 secretQuestions: service disabled (503), exit 3" "${RC}" "3"
has "06 secretQuestions: says so" "not enabled on this server"

GET_BODY=$(body question '{"secretQuestion":"Your first pet?"}')
run 03.Myself/07.myself_secretQuestion_GET.sh
expect "07 secretQuestion: the user's own, with the session" "$(calls)" "GET ${BASE}/myself/secretQuestion"
has "07 secretQuestion: prints it" "The secret question: Your first pet?"
run 03.Myself/07.myself_secretQuestion_GET.sh 'a b+c'
expect "07 secretQuestion: with a reset token instead" "$(calls)" "GET ${BASE}/myself/secretQuestion?token=a b+c"
STATUS_GET=503 run 03.Myself/07.myself_secretQuestion_GET.sh
expect "07 secretQuestion: service disabled, exit 3" "${RC}" "3"
GET_BODY=

STATUS=204 run 03.Myself/08.myself_secretQuestion_PUT.sh "Your first pet?" "Rex"
expect "08 secretQuestion PUT: PUT /myself/secretQuestion, 204, exit 0" "${RC}:$(calls)" "0:PUT ${BASE}/myself/secretQuestion"
expect "08 secretQuestion PUT: the password, the question and the answer" \
  "$(payload 1 | jq -c '[.password, .secretQuestion, .secretAnswer]')" '["s3cret","Your first pet?","Rex"]'
STATUS=503 run 03.Myself/08.myself_secretQuestion_PUT.sh "Q" "A"
expect "08 secretQuestion PUT: service disabled, exit 3" "${RC}" "3"

GET_BODY=$(body book '[{"id":"u1:g1","displayName":"Jo","mail":"jo@example.com","parentGroup":"","type":"USER"}]')
run 03.Myself/09.myself_addressBook_GET.sh 'jo*' 5
expect "09 addressBook: searches users by email order, a page at a time" "$(calls)" \
  "GET ${BASE}/myself/addressBook?searchFor=jo*&type=USER&orderBy=email&limit=5&offset=0"
has "09 addressBook: one entry per line" "  u1:g1  USER  Jo  jo@example.com"
run 03.Myself/09.myself_addressBook_GET.sh
expect "09 addressBook: no searchFor when there is nothing to search for" "$(calls | grep -c searchFor)" "0"

run 03.Myself/10.myself_addressBook_id_GET.sh 'u1:g1'
expect "10 addressBook id: the id URL-encoded in the path" "$(calls)" "GET ${BASE}/myself/addressBook/u1%3Ag1"
run 03.Myself/10.myself_addressBook_id_GET.sh
expect "10 addressBook id: without one, reads the first entry's" "$(calls)" "GET ${BASE}/myself/addressBook?limit=1
GET ${BASE}/myself/addressBook/u1%3Ag1"
GET_BODY=

echo
echo "=== 02.Files 09 to 15 ==="
GET_BODY=$(body listing '{"files":[{"fileName":"a.txt","size":5,"isDirectory":false}],"self":{"fileName":"my dir","permissions":"750","isShared":false}}')
run 02.Files/09.files_GET_query.sh "my dir" '*.txt'
expect "09 query: sort and page, without hidden files; by name, next page; metadata; glob" "$(calls)" \
"GET ${BASE}/files/my%20dir?sortBy=size&order=DESC&limit=5&offset=0&showdots=false
GET ${BASE}/files/my%20dir?sortBy=fileName&order=ASC&limit=5&offset=5
GET ${BASE}/files/my%20dir?metadata=true
GET ${BASE}/files/my%20dir/*.txt"
has "09 query: one line per entry" "  f  5  a.txt"
run 02.Files/09.files_GET_query.sh
expect "09 query: the home folder is /files" "$(calls | head -n 1)" "GET ${BASE}/files?sortBy=size&order=DESC&limit=5&offset=0&showdots=false"

GET_BODY=$(body meta '{"self":{"fileName":"a b.txt","size":5,"permissions":"640","owner":"1050","group":"1050","lastModifiedTime":1791278929000,"transferStatus":"Done"},"parent":{"fileName":"in"}}')
run 02.Files/10.files_filepath_GET_metadata.sh "/in/a b.txt"
expect "10 metadata: metadata=true, the path encoded part by part" "$(calls)" "GET ${BASE}/files/in/a%20b.txt?metadata=true"
has "10 metadata: prints it in short" "  size         5 bytes"
GET_BODY=

printf 'hello md5\n' > "${WORK}/files/up.txt"
LOCAL_MD5=$(openssl dgst -md5 -binary "${WORK}/files/up.txt" | openssl base64)
STATUS=201 run 02.Files/11.files_filepath_POST_md5.sh "${WORK}/files/up.txt" inbox
expect "11 md5: a multipart POST into the folder, with the transfer mode" "${RC}:$(calls)" "0:POST ${BASE}/files/inbox?transferMode=BINARY"
expect "11 md5: Content-MD5 is the file's MD5, base64" "$(headers | grep '^Content-MD5:')" "Content-MD5: ${LOCAL_MD5}"
STATUS=500 run 02.Files/11.files_filepath_POST_md5.sh "${WORK}/files/up.txt"
expect "11 md5: a wrong checksum's 500 is a failure; the home folder is /files" "${RC}:$(calls)" "1:POST ${BASE}/files?transferMode=BINARY"

STATUS=204 run 02.Files/12.files_filepath_PUT_rename.sh "in/a b.txt" "out/c.txt"
expect "12 PUT rename: PUT on the old path" "${RC}:$(calls)" "0:PUT ${BASE}/files/in/a%20b.txt"
expect "12 PUT rename: fileName and newFilePath" "$(payload 1 | jq -c .)" '{"fileName":"a b.txt","newFilePath":"out/c.txt"}'

STATUS=204 run 02.Files/13.files_filepath_PATCH_rename.sh "a.txt" "b.txt"
expect "13 PATCH rename: PATCH on the old path" "${RC}:$(calls)" "0:PATCH ${BASE}/files/a.txt"
expect "13 PATCH rename: one JSON Patch operation" "$(payload 1 | jq -c .)" '[{"op":"add","path":"/newFilePath","value":"b.txt"}]'
STATUS=404 run 02.Files/13.files_filepath_PATCH_rename.sh "a.txt" "b.txt"
expect "13 PATCH rename: anything but 204 is a failure" "${RC}" "1"

STATUS=204 run 02.Files/14.files_filepath_PATCH_share.sh shared "a@example.com, b@example.com" 3
expect "14 share: PATCH on the folder" "${RC}:$(calls)" "0:PATCH ${BASE}/files/shared"
expect "14 share: adds sharedDirectoryProperties, with each collaborator and the rights" \
  "$(payload 1 | jq -c '.[0] | [.op, .path, .value.collaborators, .value.shareRights, .value.isOwner]')" \
  '["add","/sharedDirectoryProperties",["a@example.com","b@example.com"],3,true]'
run 02.Files/14.files_filepath_PATCH_share.sh shared a@example.com 2
expect "14 share: rights other than 1, 3, 7 are refused before any call" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

STATUS=204 run 02.Files/15.files_filepath_PATCH_unshare.sh shared
expect "15 unshare: removes sharedDirectoryProperties" "${RC}:$(payload 1 | jq -c .)" '0:[{"op":"remove","path":"/sharedDirectoryProperties"}]'

echo
echo "=== 04.FileOperations ==="
POST_BODY=$(body op_new '{"id":"op-1","status":"IN_PROGRESS","operation":"MD5Calc","result":{"fileSize":10}}')
# Built on its own: inside a nested $(...), the JSON's braces would be expanded
OP_DONE=$(jq -n --arg md5 "${LOCAL_MD5}" '{id: "op-1", status: "DONE", operation: "MD5Calc", filePath: "/up.txt", result: {md5Checksum: $md5, fileSize: 10}}')
RULES=$(rules "fileOperations/op-1" "$(body op_done "${OP_DONE}")")
run 04.FileOperations/01.fileOperations_POST_md5calc.sh up.txt "${WORK}/files/up.txt"
expect "01 md5calc: submits, then follows the operation" "$(calls)" "POST ${BASE}/fileOperations
GET ${BASE}/fileOperations/op-1"
expect "01 md5calc: the operation and the path" "$(payload 1 | jq -c .)" '{"operation":"MD5Calc","filePath":"/up.txt"}'
expect "01 md5calc: the server's checksum matches the local copy" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'It matches')" "0:1"
printf 'other\n' > "${WORK}/files/other.txt"
run 04.FileOperations/01.fileOperations_POST_md5calc.sh up.txt "${WORK}/files/other.txt"
expect "01 md5calc: a different local file does not match, exit 1" "${RC}" "1"

GET_BODY="${WORK}/op_done.json"; RULES=
run 04.FileOperations/02.fileOperations_id_GET.sh op-1
expect "02 operation: GET /fileOperations/{id}" "$(calls)" "GET ${BASE}/fileOperations/op-1"
has "02 operation: prints its status" "MD5Calc of /up.txt: DONE"
GET_BODY=

printf '0123456789abcdefghijKLMNO' > "${WORK}/files/chunks.bin"
POST_BODY=$(body op_up '{"id":"op-2","status":"IN_PROGRESS","operation":"Upload"}')
run 04.FileOperations/03.fileOperations_id_PUT_chunked.sh "${WORK}/files/chunks.bin" inbox 10
expect "03 chunked: declares the upload, then three PUTs" "$(calls)" "POST ${BASE}/fileOperations
PUT ${BASE}/fileOperations/op-2
PUT ${BASE}/fileOperations/op-2
PUT ${BASE}/fileOperations/op-2"
expect "03 chunked: the path in the folder" "$(payload 1 | jq -r .filePath)" "/inbox/chunks.bin"
expect "03 chunked: Content-Range of each chunk, the last one shorter" "$(headers | grep '^Content-Range:' | tr '\n' '|')" \
  "Content-Range: bytes 0-9/25|Content-Range: bytes 10-19/25|Content-Range: bytes 20-24/25|"
expect "03 chunked: the chunks together are the file" "$(payload 2)$(payload 3)$(payload 4)" "0123456789abcdefghijKLMNO"
STATUS=400 run 04.FileOperations/03.fileOperations_id_PUT_chunked.sh "${WORK}/files/chunks.bin" "" 10
expect "03 chunked: stops at the first refused chunk" "${RC}:$(calls | grep -c '^PUT')" "1:1"

STATUS=200 run 04.FileOperations/04.fileOperations_id_POST_multipart.sh "${WORK}/files/up.txt" inbox
expect "04 multipart: declares, then POSTs the content to the operation" "${RC}:$(calls)" "0:POST ${BASE}/fileOperations
POST ${BASE}/fileOperations/op-2"

POST_BODY=$(body op_cancel '{"id":"op-3","status":"IN_PROGRESS","operation":"Upload"}')
STATUS_GET=404 run 04.FileOperations/05.fileOperations_id_DELETE.sh
expect "05 cancel: declares an upload, cancels it, confirms it is gone" "${RC}:$(calls)" "0:POST ${BASE}/fileOperations
DELETE ${BASE}/fileOperations/op-3
GET ${BASE}/fileOperations/op-3"
STATUS_GET=200 run 04.FileOperations/05.fileOperations_id_DELETE.sh op-9
expect "05 cancel: an operation still there afterwards is a failure" "${RC}:$(calls | head -n 1)" "1:DELETE ${BASE}/fileOperations/op-9"
POST_BODY=

echo
echo "=== 05.Transfers ==="
GET_BODY=$(body transfers '[{"transferId":"VFgx","startTime":"Tue, 06 Oct 2026 12:00:00 +0300","direction":"Incoming","status":"Processed","protocol":"ssh","filename":"a.txt"}]')
run 05.Transfers/01.transfers_GET.sh 3
expect "01 transfers: the latest, a page at a time" "$(calls | sed -n 1p)" "GET ${BASE}/transfers?limit=3&offset=0"
calls | sed -n 2p | grep -qE "^GET ${BASE}/transfers\?status=Failed&status=Aborted&startTimeAfter=[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} 00:00:00 [+-][0-9]{4}&limit=3$" \
    && pass "01 transfers: today's failed and aborted, status repeated, from midnight in RFC 2822" || fail "01 transfers: $(calls | sed -n 2p)"
expect "01 transfers: the outgoing ones the server started, over SSH" "$(calls | sed -n 3p)" \
  "GET ${BASE}/transfers?direction=Outgoing&actionBy=Server&protocol=ssh&limit=3"
has "01 transfers: one line per transfer" "Incoming  Processed  ssh  a.txt"

RULES=$(rules "transfers?limit=1" "${GET_BODY}" "transfers/VFgx" "$(body detail '{"transferType":"User upload","file":"a.txt","size":5,"status":"Processed","transferSite":"(none)","protocol":"http","mode":"BINARY","realFile":"/home/x/a.txt"}')")
run 05.Transfers/02.transfers_id_GET.sh
expect "02 transfer: without an id, the latest one's" "$(calls)" "GET ${BASE}/transfers?limit=1
GET ${BASE}/transfers/VFgx"
has "02 transfer: prints it in short" "  User upload of a.txt, 5 bytes, Processed"
RULES=; GET_BODY=

POST_BODY=$(body pull '{"message":"Transfer pull event has been successfully submitted","link":"https://x/api/v2.0/transfers?operationIndex=idx-1&expectedFilesCount=2"}')
GET_BODY=$(body summary '{"totalCount":2,"successful":2,"failed":0,"inRetry":0,"inProgress":0,"onHold":0}')
run 05.Transfers/03.transfers_operations_POST_pull.sh mysite landing idx-1
expect "03 pull: POST the operation, then the pull summary" "${RC}:$(calls)" "0:POST ${BASE}/transfers/operations
GET ${BASE}/transfers/pullSummary/idx-1"
expect "03 pull: the site, the folder, the operationIndex, awaitResult" \
  "$(payload 1 | jq -c '[.operation, .data.site, .data.destinationDirectory, .data.operationIndex, .data.awaitResult]')" \
  '["pull","mysite","/landing","idx-1",true]'
has "03 pull: reads expectedFilesCount from the link" "Files expected: 2"

run 05.Transfers/04.transfers_pullSummary_GET.sh idx-1
expect "04 pull summary: all done, exit 0" "${RC}:$(calls)" "0:GET ${BASE}/transfers/pullSummary/idx-1"
has "04 pull summary: prints the counts" "2 file(s): 2 successful, 0 failed"
GET_BODY=$(body summary_retry '{"totalCount":2,"successful":1,"failed":0,"inRetry":1,"inProgress":0,"onHold":0}')
run 05.Transfers/04.transfers_pullSummary_GET.sh idx-1
expect "04 pull summary: still in retry, exit 3" "${RC}" "3"
GET_BODY=$(body summary_failed '{"totalCount":2,"successful":1,"failed":1,"inRetry":0,"inProgress":0,"onHold":0}')
run 05.Transfers/04.transfers_pullSummary_GET.sh idx-1
expect "04 pull summary: a failure, exit 1" "${RC}" "1"

GET_BODY="${WORK}/transfers.json"
POST_BODY=$(body push '{"message":"Transfer push event has been successfully submitted","link":"https://x"}')
run 05.Transfers/05.transfers_operations_POST_push.sh mysite out/a.txt
expect "05 push: synchronous by default" "$(payload 1 | jq -c '[.operation, .data.file, .data.site, .data.asynchronousCall]')" '["push","/out/a.txt","mysite",false]'
calls | sed -n 2p | grep -qE "^GET ${BASE}/transfers\?operationIndex=eu-push-[0-9]+$" \
    && [ "$(payload 1 | jq -r .data.operationIndex)" = "$(calls | sed -n 2p | sed 's/.*operationIndex=//')" ] \
    && pass "05 push: finds the transfer in the log by the operationIndex it sent" || fail "05 push: $(calls)"
STATUS=202 run 05.Transfers/05.transfers_operations_POST_push.sh mysite out/a.txt async
expect "05 push: async asks for an asynchronous call, and 202 is a success" "${RC}:$(payload 1 | jq -c .data.asynchronousCall)" "0:true"

run 05.Transfers/06.transfers_operations_POST_folderMonitor.sh fm_from fm_to '*.txt'
expect "06 folder monitor: the folders, the pattern and its type" \
  "$(payload 1 | jq -c '[.operation, .data.downloadFolder, .data.uploadFolder, .data.filePattern, .data.filePatternType, .data.subFolderMaxDepth]')" \
  '["folderMonitor","/fm_from","/fm_to","*.txt","glob",1]'
expect "06 folder monitor: every field the reference requires" \
  "$(payload 1 | jq -c '.data | [has("fileCaseSensitive"), has("subFolderPattern"), has("subFolderPatternType"), has("subFolderCaseSensitive")] | unique')" '[true]'
GET_BODY=

POST_BODY=$(body mdn '{"fileIntegrityResult":"OK","signatureResult":"VALID"}')
run 05.Transfers/07.transfers_id_operations_POST_verifymdn.sh VFgx
expect "07 verifymdn: POST on the transfer, the operation in the query" "${RC}:$(calls)" "0:POST ${BASE}/transfers/VFgx/operations?operation=verifymdn"
has "07 verifymdn: prints both results" "Signature:      VALID"
POST_BODY=

echo
echo "=== 06.ServerTime ==="
GET_BODY=$(body time '{"requestArrivalTime":"2026-10-06T12:28:47.787+0300","responseDepartureTime":"2026-10-06T12:28:47.792+0300"}')
run 06.ServerTime/01.serverTime_GET.sh
expect "01 serverTime: GET /serverTime" "${RC}:$(calls)" "0:GET ${BASE}/serverTime"
has "01 serverTime: compares the clocks, reading the +0300 offset" "second(s) from this machine's."
GET_BODY=

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_enduser_api: PASS"
else
    echo "test_bash_enduser_api: FAIL"
fi
exit "${FAILED}"
