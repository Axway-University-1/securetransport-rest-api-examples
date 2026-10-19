#!/bin/bash
# ==============================================================================
# Run the EndUser use cases (EndUser/UseCases/*) against a stub curl, and check
# the calls each script makes.
#
# 02-knowing-yourself, 03-files-and-folders, 04-larger-files and 05-checking-transfers
# follow the same way: each script starts with the check for an active session
# (st_session in UseCases/session.sh: a jar that is missing or refused is a login),
# and then makes its own calls, which are read back here by method, URL, query,
# form and body, with the answers each script acts on (a 404 for a missing
# file, a 403 for a folder that is not empty, a wrong checksum, a 403 for an
# account that may not use the transfers service).
#
# 01-authentication: Basic authentication on a call (-u, no cookie), a call with
# no credentials that must be refused with 401, the login that keeps a cookie jar
# and the csrfToken, the call with the cookie only, the csrfToken header, the
# recovery from an expired session, the logout that proves the old cookie is dead,
# and the cleanup. Each script's exit code is checked too, so a server answer the
# script does not expect must stop it.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
UC_ROOT="${REPO}/EndUser/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_enduser_usecases"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasre() { if printf '%s\n' "${OUT}" | grep -qE -- "$2"; then pass "$1"; else fail "$1  (nothing like '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

# the stub, behind the wrapper that answers each method with its own status (STUB_STATUS_PATCH=403 and so on)
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"

# The use case sits two folders under EndUser/, next to "API 2.0/bash" with its settings
mkdir -p "${WORK}/tree/UseCases"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp -R "${UC_ROOT}/." "${WORK}/tree/UseCases/"
UC="${WORK}/tree/UseCases/01-authentication"
BASE="https://st.example.com:8444/api/v2.0"
echo '{"name":"john","type":"user"}' > "${WORK}/me.json"
# body NAME JSON: a canned answer, in a file
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }

# rules TEXT FILE [TEXT FILE...]: a STUB_CURL_GET_RULES file, the body to answer a GET whose URL has the text
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# run SCRIPT: STATUS sets every answer, STATUS_GET only the GETs, CSRF a csrfToken header on the login
run() {
    local rel="$1"; shift
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/me.json}" STUB_CURL_GET_RULES="${RULES:-}" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" \
          STUB_CURL_CSRF="${CSRF:-}" STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
headers() { printf '%s\n' "${OUT}" | sed -n 's/^HEADER: //p'; }
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | wc -l | tr -d ' '; }

echo "=== 01 Basic authentication on one call ==="
run 01.basic_auth_GET_myself.sh
expect "01: one GET /myself" "$(calls)" "GET ${BASE}/myself"
has "01: sends the user and password with -u" "BASIC_AUTH: "
hasnt "01: and no cookie, there is no session" "COOKIE:"
has "01: prints who you are" "You are john (user)"
expect "01: exit 0" "${RC}" "0"
STATUS=401 run 01.basic_auth_GET_myself.sh
expect "01: a refused password stops it (exit 1)" "${RC}" "1"

echo "=== 02 no credentials ==="
STATUS=401 run 02.no_credentials_GET_myself.sh
expect "02: one GET /myself" "$(calls)" "GET ${BASE}/myself"
hasnt "02: with neither -u nor a cookie" "BASIC_AUTH:"
expect "02: 401 is the expected answer (exit 0)" "${RC}" "0"
STATUS=200 run 02.no_credentials_GET_myself.sh
expect "02: a 200 is not (exit 1)" "${RC}" "1"

echo "=== 03 login: the session and the csrfToken ==="
rm -f "${UC}"/session.cookie.jar "${UC}"/state.local.csrf
CSRF=tok123 run 03.session_login_POST.sh
expect "03: one POST /myself" "$(calls)" "POST ${BASE}/myself"
has "03: with the user and password" "BASIC_AUTH: "
hasre "03: writing the cookie jar of this use case, not myCookie.jar" "^COOKIE_JAR_WRITE: .*/01-authentication/session\.cookie\.jar$"
expect "03: saves the csrfToken" "$(cat "${UC}/state.local.csrf")" "tok123"
expect "03: exit 0" "${RC}" "0"
STATUS=401 run 03.session_login_POST.sh
expect "03: a refused login leaves no jar and exits 1" "${RC}:$([ -f "${UC}/session.cookie.jar" ] && echo jar || echo none)" "1:none"

echo "=== 04 the cookie, no password ==="
rm -f "${UC}/session.cookie.jar"
run 04.session_cookie_GET_myself.sh
expect "04: with no session it says to run 03 and exits 2, sending nothing" "${RC}:$(ncalls)" "2:0"
touch "${UC}/session.cookie.jar"
run 04.session_cookie_GET_myself.sh
expect "04: one GET /myself" "$(calls)" "GET ${BASE}/myself"
hasre "04: sends the cookie jar" "^COOKIE: .*/01-authentication/session\.cookie\.jar$"
hasnt "04: and no password" "BASIC_AUTH:"
STATUS=401 run 04.session_cookie_GET_myself.sh
expect "04: a refused session exits 1" "${RC}" "1"

echo "=== 05 the csrfToken header ==="
echo tok123 > "${UC}/state.local.csrf"
run 05.session_csrf_header_GET_myself.sh
has "05: sends the csrfToken header" "HEADER: csrfToken: tok123"
hasre "05: and the cookie" "^COOKIE: .*/01-authentication/session\.cookie\.jar$"
rm -f "${UC}/state.local.csrf"
run 05.session_csrf_header_GET_myself.sh
expect "05: with no saved token it sends nothing and exits 1" "${RC}:$(ncalls)" "1:0"

echo "=== 06 an expired session, then a new login ==="
STATUS_GET=401 run 06.session_expired_recovery.sh
expect "06: the stale call, then the login, then the call with the new session" \
  "$(calls | tr '\n' ' ')" "GET ${BASE}/myself POST ${BASE}/myself GET ${BASE}/myself "
has "06: says the session is lost" "The session is lost. Logging in again..."
STATUS_GET=403 run 06.session_expired_recovery.sh
has "06: a 403 is a lost session too" "The session is lost"
STATUS_GET=500 run 06.session_expired_recovery.sh
expect "06: a 500 is not a lost session: no login, exit 1" "${RC}:$(ncalls)" "1:1"

echo "=== 07 logout, then the old cookie is refused ==="
touch "${UC}/session.cookie.jar"; echo tok > "${UC}/state.local.csrf"
STATUS_GET=401 run 07.logout_DELETE.sh
expect "07: DELETE /myself, then a GET with the old cookie" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/myself GET ${BASE}/myself "
expect "07: the 401 proves it, exit 0, jar and token removed" "${RC}:$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "0:gone"
touch "${UC}/session.cookie.jar"
STATUS_GET=200 run 07.logout_DELETE.sh
expect "07: an old cookie that still works is reported (exit 1)" "${RC}" "1"
rm -f "${UC}/session.cookie.jar"
run 07.logout_DELETE.sh
expect "07: with no session it says to run 03 and exits 2" "${RC}:$(ncalls)" "2:0"

echo "=== 99 cleanup and 00 run_all ==="
touch "${UC}/session.cookie.jar"; echo tok > "${UC}/state.local.csrf"
STATUS_GET=401 run 99.cleanup_DELETE.sh
expect "99: removes the jar and the token" "$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "gone"
rm -f "${UC}/session.cookie.jar"
run 99.cleanup_DELETE.sh
expect "99: with no session it sends nothing" "$(ncalls)" "0"

# the stub answers 200 to a GET with no credentials, so 02 stops run_all: that shows the stop
run 00.run_all.sh
has "00: stops at the first failing script (02 got a 200)" "02.no_credentials_GET_myself failed."
has "00: and still runs the cleanup" "Cleaned up."
expect "00: exit 1" "${RC}" "1"
# a server that answers 401 to the no-credentials call (a GET) but 200 to the rest cannot be told apart by
# method for the GETs, so the full run is the lab check's job: here every script was run above on its own.

# ---------------------------------------------------------------- the later use cases
# uc NAME: work in that use case, with a session jar as 03 of 01-authentication leaves it (the stub writes none)
uc() { UC="${WORK}/tree/UseCases/$1"; touch "${UC}/session.cookie.jar"; }
# ucalls: the calls of the script, without the check for an active session that starts it
ucalls() { calls | sed 1d; }
urun() { touch "${UC}/session.cookie.jar"; run "$@"; }
BASE_FILES="${BASE}/files"

echo "=== Every later script starts with the check for a session, and logs in when there is none ==="
for rel in 02-knowing-yourself/01.myself_GET.sh 03-files-and-folders/03.files_GET_list.sh 04-larger-files/06.files_POST_bulk.sh 05-checking-transfers/01.transfers_GET.sh; do
    uc "$(dirname "${rel}")"; rm -f "${UC}/session.cookie.jar"
    run "../${rel}"
    expect "${rel}: with no jar it logs in first (POST /myself with the user and password), then goes on" \
      "$(calls | head -1)" "POST ${BASE}/myself"
    has "${rel}: and says so" "There is no session yet. Logging in..."
done
uc 02-knowing-yourself
STATUS_GET=401 urun ../02-knowing-yourself/01.myself_GET.sh
has "a session the server refuses (401) is a login too" "The session is no longer active (HTTP 401). Logging in..."
rm -f "${UC}/session.cookie.jar"
STUB_STATUS_POST=401 run ../02-knowing-yourself/01.myself_GET.sh
expect "a login that fails stops the script (exit 1) before its own call" "${RC}:$(ncalls)" "1:1"
STATUS_GET=500 urun ../02-knowing-yourself/01.myself_GET.sh
expect "a 500 is not a lost session: no login" "$(calls | grep -c POST)" "0"

echo "=== 02-knowing-yourself ==="
uc 02-knowing-yourself
urun ../02-knowing-yourself/01.myself_GET.sh
expect "01: GET /myself with the cookie, and nothing else" "$(ucalls)" "GET ${BASE}/myself"
has "01: prints the answer" '"name": "john"'
STATUS_GET=403 STUB_STATUS_GET=403 urun ../02-knowing-yourself/01.myself_GET.sh
expect "01: a refused answer exits 1 (after the login the check made)" "${RC}" "1"
urun ../02-knowing-yourself/02.myself_GET_narrowed.sh
expect "02: the object, then the same with ?fields=name" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/myself GET ${BASE}/myself?fields=name "
has "02: one value" "One value:        john"
has "02: a few, as JSON" '{"name":"john","type":"user","uid":null,"gid":null}'
has "02: a null becomes the default" "language = none"
has "02: sees that the server ignored fields=" "So /myself ignores fields="
urun ../02-knowing-yourself/03.myself_passwordExpired_GET.sh
GET_BODY=$(body expired_false '{"expired": false}') urun ../02-knowing-yourself/03.myself_passwordExpired_GET.sh
expect "03: GET /myself/passwordExpired" "$(ucalls)" "GET ${BASE}/myself/passwordExpired"
expect "03: not expired is exit 0" "${RC}" "0"
GET_BODY=$(body expired_true '{"expired": true, "changePasswordURL": "https://x/change"}') urun ../02-knowing-yourself/03.myself_passwordExpired_GET.sh
expect "03: expired is exit 3, with the address to change it" "${RC}" "3"
has "03: names the change address" "https://x/change"
GET_BODY=$(body servertime '{"requestArrivalTime": "2026-10-15T07:13:01.288+0300", "responseDepartureTime": "2026-10-15T07:13:01.291+0300"}') urun ../02-knowing-yourself/04.serverTime_GET.sh
expect "04: GET /serverTime" "$(ucalls)" "GET ${BASE}/serverTime"
has "04: prints both times" "Request arrived:  2026-10-15T07:13:01.288+0300"
GET_BODY=$(body book '[{"displayName":"Local","mail":"","type":"Group"},{"displayName":"ann","mail":"ann@example.com","type":"User"},{"displayName":"bob","mail":"","type":"User"}]') urun ../02-knowing-yourself/05.myself_addressBook_GET.sh
expect "05: GET /myself/addressBook" "$(ucalls)" "GET ${BASE}/myself/addressBook"
has "05: counts the entries" "Entries: 3"
has "05: counts by type" "  User: 2"
has "05: lists the users that have an e-mail, and not the others" "ann  <ann@example.com>"
hasnt "05: and not a user with none" "bob"
urun ../02-knowing-yourself/99.cleanup_DELETE.sh
expect "99: logs out with the cookie (DELETE /myself) and removes the jar" "$(calls | tail -1):$([ -e "${UC}/session.cookie.jar" ] && echo kept || echo gone)" "DELETE ${BASE}/myself:gone"
RULES=$(rules addressBook "${WORK}/book.json" passwordExpired "${WORK}/expired_false.json" serverTime "${WORK}/servertime.json") urun ../02-knowing-yourself/00.run_all.sh
expect "00: runs every script, then 99, and exits 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== ')" "0:6"

echo "=== 03-files-and-folders ==="
F="${BASE_FILES}/example_uc_files"
uc 03-files-and-folders
STUB_STATUS_GET=404 STUB_STATUS_POST=201 urun ../03-files-and-folders/01.folder_POST.sh
expect "01: looks for the folder, then creates it with POST" "$(ucalls | tr '\n' ' ')" "GET ${F}?metadata=true POST ${F} "
expect "01: with the body that says it is a directory" "$(payload 1 | jq -r .isDirectory)" "true"
STUB_STATUS_GET=404 STUB_STATUS_POST=409 urun ../03-files-and-folders/01.folder_POST.sh
expect "01: a refused create is exit 1" "${RC}" "1"
urun ../03-files-and-folders/01.folder_POST.sh
has "01: a folder that is there is left alone" "already exists. Nothing to create."
expect "01: ... with no POST, exit 0" "$(ucalls | grep -c POST):${RC}" "0:0"
urun ../03-files-and-folders/02.files_POST_upload.sh
expect "02: POST /files/<folder>, the folder in the URL" "$(ucalls)" "POST ${F}"
has "02: the name in the form" "filename=notes.txt"
STUB_STATUS_POST=404 urun ../03-files-and-folders/02.files_POST_upload.sh
expect "02: a 404 (no folder) is exit 1" "${RC}" "1"
urun ../03-files-and-folders/03.files_GET_list.sh
expect "03: the list, sorted and limited, the glob, the folder's own metadata" "$(ucalls | tr '\n' ' ')" \
  "GET ${F} GET ${F}?sortBy=size&order=DESC&limit=5&showdots=false GET ${F}/*.txt GET ${F}?metadata=true "
urun ../03-files-and-folders/04.files_GET_read.sh
expect "04: GET /files/<folder>/<file>" "$(ucalls)" "GET ${F}/notes.txt"
expect "04: and a copy is kept in downloaded_files" "$([ -f "${UC}/downloaded_files/notes.txt" ] && echo saved)" "saved"
STUB_STATUS_GET=404 urun ../03-files-and-folders/04.files_GET_read.sh
expect "04: a 404 is exit 1 with the hint to upload first, and no empty file kept" "${RC}:$([ -f "${UC}/downloaded_files/notes.txt" ] && echo kept || echo gone)" "1:gone"
has "04: the hint" "Upload it first with 02.files_POST_upload.sh."
GET_BODY=$(body meta '{"self":{"fileName":"notes.txt","size":28,"permissions":"640","lastModifiedTime":1792037563488,"customProperties":{"MD5":"abc"}}}') urun ../03-files-and-folders/05.files_GET_metadata.sh
expect "05: GET /files/<folder>/<file>?metadata=true" "$(ucalls)" "GET ${F}/notes.txt?metadata=true"
has "05: the size" "size      28 bytes"
has "05: the MD5 the server recorded" "MD5       abc"
urun ../03-files-and-folders/06.files_POST_overwrite.sh
expect "06: the same upload again, then a read of it" "$(ucalls | tr '\n' ' ')" "POST ${F} GET ${F}/notes.txt "
urun ../03-files-and-folders/07.files_PATCH_rename.sh
expect "07: PATCH of the file" "$(ucalls)" "PATCH ${F}/notes.txt"
expect "07: the patch body" "$(payload 1 | jq -c .)" '[{"op":"add","path":"/newFilePath","value":"/example_uc_files/notes_renamed.txt"}]'
STUB_STATUS_PATCH=403 urun ../03-files-and-folders/07.files_PATCH_rename.sh
expect "07: a refused rename is exit 1" "${RC}" "1"
STUB_STATUS_DELETE=204 STUB_STATUS_GET=404 urun ../03-files-and-folders/08.files_DELETE_file.sh
expect "08: DELETE the renamed file, then read it again" "$(ucalls | tr '\n' ' ')" "DELETE ${F}/notes_renamed.txt GET ${F}/notes_renamed.txt "
STUB_STATUS_DELETE=204 STUB_STATUS_GET=200 urun ../03-files-and-folders/08.files_DELETE_file.sh
expect "08: a file that is still there afterwards is exit 1" "${RC}" "1"
STUB_STATUS_DELETE=404 urun ../03-files-and-folders/08.files_DELETE_file.sh
expect "08: deleting what is not there is exit 1" "${RC}" "1"
STUB_STATUS_POST=201 STUB_STATUS_DELETE_SEQ="403 204 204" STUB_COUNTER="${WORK}/ctr9" urun ../03-files-and-folders/09.folder_DELETE.sh
rm -f "${WORK}"/ctr9.*
expect "09: puts a file in, tries the folder, deletes the file, then the folder" "$(ucalls | tr '\n' ' ')" \
  "POST ${F} DELETE ${F} DELETE ${F}/notes.txt DELETE ${F} "
expect "09: a refused folder, then done: exit 0" "${RC}" "0"
STUB_STATUS_POST=201 STUB_STATUS_DELETE=204 urun ../03-files-and-folders/09.folder_DELETE.sh
expect "09: a folder that is deleted at once while it has a file is not the behaviour shown: exit 1" "${RC}" "1"
urun ../03-files-and-folders/99.cleanup_DELETE.sh
expect "99: deletes the two file names, the folder last, by exact name, then logs out" "$(calls | tr '\n' ' ')" \
  "DELETE ${F}/notes_renamed.txt DELETE ${F}/notes.txt DELETE ${F} DELETE ${BASE}/myself "

echo "=== 04-larger-files ==="
F="${BASE_FILES}/example_uc_large"
uc 04-larger-files
STUB_STATUS_GET=404 STUB_STATUS_POST=201 urun ../04-larger-files/01.folder_POST.sh
expect "01: looks for the folder, then creates it" "$(ucalls | tr '\n' ' ')" "GET ${F}?metadata=true POST ${F} "
STUB_STATUS_POST=201 urun ../04-larger-files/02.files_POST_md5.sh
expect "02: two uploads into the folder, as BINARY" "$(ucalls | tr '\n' ' ')" "POST ${F}?transferMode=BINARY POST ${F}?transferMode=BINARY "
has "02: the first carries a Content-MD5 header" "HEADER: Content-MD5: "
expect "02: a wrong checksum that is accepted (201 for both) is exit 1" "${RC}" "1"
STUB_STATUS_POST_SEQ="201 500" STUB_COUNTER="${WORK}/ctr2" urun ../04-larger-files/02.files_POST_md5.sh
rm -f "${WORK}"/ctr2.*
expect "02: right is 201, wrong is refused: exit 0" "${RC}" "0"
STUB_STATUS_POST=500 urun ../04-larger-files/02.files_POST_md5.sh
expect "02: a right checksum that is refused is exit 1" "${RC}" "1"
LOCAL_MD5=$(cd "${UC}" && source ./lib.sh >/dev/null 2>&1; f="${WORK}/s.bin"; st_sample "${f}" 100000 md5; st_md5 "${f}")
OP=$(body op_done "{\"id\":\"op1\",\"status\":\"DONE\",\"result\":{\"md5Checksum\":\"${LOCAL_MD5}\",\"fileSize\":100000}}")
STUB_CURL_POST_BODY="${OP}" urun ../04-larger-files/03.fileOperations_POST_md5calc.sh
expect "03: POST /fileOperations (MD5Calc) and no wait when it is done" "$(ucalls)" "POST ${BASE}/fileOperations"
has "03: the checksums match" "They match."
OPBAD=$(body op_bad '{"id":"op1","status":"DONE","result":{"md5Checksum":"AAAAAAAAAAAAAAAAAAAAAA==","fileSize":100000}}')
STUB_CURL_POST_BODY="${OPBAD}" urun ../04-larger-files/03.fileOperations_POST_md5calc.sh
expect "03: checksums that differ are exit 1" "${RC}" "1"
OPWAIT=$(body op_wait '{"id":"op1","status":"IN_PROGRESS"}')
STUB_CURL_POST_BODY="${OPWAIT}" GET_BODY="${OP}" urun ../04-larger-files/03.fileOperations_POST_md5calc.sh
expect "03: an operation in progress is followed with GET /fileOperations/<id> until done" "$(ucalls | tr '\n' ' ')" "POST ${BASE}/fileOperations GET ${BASE}/fileOperations/op1 "
STUB_CURL_POST_BODY="${WORK}/me.json" urun ../04-larger-files/03.fileOperations_POST_md5calc.sh
expect "03: no operation id is exit 1" "${RC}" "1"
STUB_CURL_POST_BODY="$(body opid '{"id":"op9"}')" urun ../04-larger-files/04.fileOperations_PUT_chunked.sh
expect "04: declares the upload, then three PUTs to the id" "$(ucalls | tr '\n' ' ')" \
  "POST ${BASE}/fileOperations PUT ${BASE}/fileOperations/op9 PUT ${BASE}/fileOperations/op9 PUT ${BASE}/fileOperations/op9 "
expect "04: with the ranges of 250000 bytes in pieces of 100000" "$(headers | grep Content-Range | tr '\n' ' ')" \
  "Content-Range: bytes 0-99999/250000 Content-Range: bytes 100000-199999/250000 Content-Range: bytes 200000-249999/250000 "
STUB_CURL_POST_BODY="$(body opid '{"id":"op9"}')" STUB_STATUS_PUT=500 urun ../04-larger-files/04.fileOperations_PUT_chunked.sh
expect "04: a refused piece stops the upload after one PUT (exit 1)" "$(ucalls | grep -c PUT):${RC}" "1:1"
STUB_CURL_POST_BODY="${WORK}/me.json" urun ../04-larger-files/04.fileOperations_PUT_chunked.sh
expect "04: no operation id: nothing is sent (exit 1)" "$(ucalls | grep -c PUT):${RC}" "0:1"
STUB_CURL_POST_BODY="$(body opid '{"id":"op9"}')" urun ../04-larger-files/05.fileOperations_POST_multipart.sh
expect "05: declares it, then POSTs the content to the id" "$(ucalls | tr '\n' ' ')" "POST ${BASE}/fileOperations POST ${BASE}/fileOperations/op9 "
has "05: with the name in the form" "filename=example_multipart.bin"
STUB_STATUS_POST=201 urun ../04-larger-files/06.files_POST_bulk.sh
expect "06: three uploads into the folder" "$(ucalls | tr '\n' ' ')" "POST ${F} POST ${F} POST ${F} "
STUB_STATUS_POST_SEQ="201 500" STUB_COUNTER="${WORK}/ctr6" urun ../04-larger-files/06.files_POST_bulk.sh
rm -f "${WORK}"/ctr6.*
expect "06: stops at the first refusal, after one file (exit 1)" "$(ucalls | grep -c POST):${RC}" "2:1"
urun ../04-larger-files/99.cleanup_DELETE.sh
expect "99: deletes the six file names, then the folder, then logs out" "$(calls | tr '\n' ' ')" \
  "DELETE ${F}/example_md5.bin DELETE ${F}/example_chunked.bin DELETE ${F}/example_multipart.bin DELETE ${F}/example_bulk_1.txt DELETE ${F}/example_bulk_2.txt DELETE ${F}/example_bulk_3.txt DELETE ${F} DELETE ${BASE}/myself "

echo "=== 05-checking-transfers ==="
T="${BASE}/transfers"
uc 05-checking-transfers
LIST=$(body tlist '[{"transferId":"aWQ9PQ==","filename":"notes.txt","direction":"Incoming","protocol":"http","status":"Processed","startTime":"Thu, 15 Oct 2026 07:12:46 +0300"},{"transferId":"b2s=","filename":"b.txt","direction":"Outgoing","protocol":"ssh","status":"Failed","startTime":"Thu, 15 Oct 2026 07:12:50 +0300"}]')
GET_BODY="${LIST}" urun ../05-checking-transfers/01.transfers_GET.sh
expect "01: GET /transfers with limit 5, offset 0" "$(ucalls)" "GET ${T}?limit=5&offset=0"
has "01: one line per transfer" "  notes.txt  Incoming  http  Processed"
GET_BODY="${LIST}" urun ../05-checking-transfers/01.transfers_GET.sh 20
expect "01: the limit given" "$(ucalls)" "GET ${T}?limit=20&offset=0"
urun ../05-checking-transfers/01.transfers_GET.sh 0
expect "01: a limit that is not a whole number above 0 is exit 2 and sends nothing" "${RC}:$(ncalls)" "2:0"
STUB_STATUS_GET=403 STATUS_GET=403 urun ../05-checking-transfers/01.transfers_GET.sh
has "01: a 403 says the account may not use the transfers service" "may not use the transfers web service"
GET_BODY="${LIST}" urun ../05-checking-transfers/02.transfers_GET_filtered.sh
expect "02: six counts, each a filter in the query" "$(ucalls | sed 's/startTimeAfter=.*&/startTimeAfter=T\&/' | tr '\n' ' ')" \
  "GET ${T}?limit=100 GET ${T}?direction=Outgoing&limit=100 GET ${T}?direction=Incoming&limit=100 GET ${T}?protocol=http&limit=100 GET ${T}?status=Failed&status=Aborted&limit=100 GET ${T}?startTimeAfter=T&limit=100 "
has "02: prints the count" "all:                               2"
GET_BODY="${LIST}" urun ../05-checking-transfers/03.transfers_id_GET.sh
expect "03: the newest, then that one by its id, encoded" "$(ucalls | tr '\n' ' ')" "GET ${T}?limit=1 GET ${T}/aWQ9PQ%3D%3D "
GET_BODY="$(body empty '[]')" urun ../05-checking-transfers/03.transfers_id_GET.sh
expect "03: no transfer at all is exit 2 and no second call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "2:1"
GET_BODY="${LIST}" urun ../05-checking-transfers/04.transfers_summary.sh
expect "04: one GET with limit 100" "$(ucalls)" "GET ${T}?limit=100"
has "04: counts by status" "  Processed: 1"
has "04: and by direction" "  Outgoing: 1"
urun ../05-checking-transfers/99.cleanup_DELETE.sh
expect "99: only the logout" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/myself "

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}"/*/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    ref=$(sed -n 's/^# - Copied from \(EndUser\/API 2.0\/bash\/[^ ,]*\).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "$(dirname "${s}")")/$(basename "${s}")"
    if [ -z "${ref}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${ref}" ]; then pass "${n}: copied from ${ref}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${ref})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_enduser_usecases: FAIL"; exit 1; fi
echo "test_bash_enduser_usecases: PASS"
