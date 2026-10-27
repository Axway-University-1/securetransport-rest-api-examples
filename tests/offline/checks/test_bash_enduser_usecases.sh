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
REPO="$(cd ../.. && pwd)"
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
has "02: says the end user API has no fields parameter" "The end user API has no fields parameter"
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
has "03: says what each of the four lists is" "The folder:"
has "03: the largest first" "The largest first, at most 5, no hidden files:"
has "03: the glob" "Only the .txt files (a glob in the path):"
has "03: and the folder itself" "The folder itself, without its list (metadata=true):"
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

echo "=== 00.run_all of 03, 04 and 05: it stops at the first step that fails, and cleans up either way ==="
uc 03-files-and-folders
STUB_STATUS_GET=404 STUB_STATUS_POST=409 urun ../03-files-and-folders/00.run_all.sh
expect "03 00: a folder that cannot be made is exit 1" "${RC}" "1"
has "03 00: it names the step that failed" "01.folder_POST failed."
hasnt "03 00: and does not go on to the upload" "=== 02.files_POST_upload ==="
has "03 00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="
uc 04-larger-files
STUB_STATUS_GET=404 STUB_STATUS_POST=409 urun ../04-larger-files/00.run_all.sh
expect "04 00: a folder that cannot be made is exit 1" "${RC}" "1"
has "04 00: it names the step that failed" "01.folder_POST failed."
hasnt "04 00: and does not go on to the uploads" "=== 02.files_POST_md5 ==="
has "04 00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="
uc 05-checking-transfers
STUB_STATUS_GET=500 urun ../05-checking-transfers/00.run_all.sh
expect "05 00: a server error on the first call is exit 1" "${RC}" "1"
has "05 00: it names the step that failed" "01.transfers_GET failed."
hasnt "05 00: and does not go on to the next" "=== 02.transfers_GET_filtered ==="
has "05 00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="

echo "=== 06-sharing-a-folder ==="
F="${BASE_FILES}/example_uc_shared"
uc 06-sharing-a-folder
ALLOWED=$(body sharing_yes '{"sharingAllowed":true,"contact":{"email":"owner@example.com"}}')
DENIED=$(body sharing_no '{"sharingAllowed":false,"contact":{"email":""}}')
GET_BODY="${ALLOWED}" urun ../06-sharing-a-folder/01.sharing_GET_myself.sh
expect "01: GET /myself, and nothing else" "$(ucalls)" "GET ${BASE}/myself"
has "01: says sharing is allowed, with the address" "sharingAllowed: true; e-mail address of the account: owner@example.com"
expect "01: exit 0" "${RC}" "0"
GET_BODY="${DENIED}" urun ../06-sharing-a-folder/01.sharing_GET_myself.sh
expect "01: an account with no e-mail may not share: exit 3" "${RC}" "3"
has "01: and it says why" "it has no e-mail address"
has "01: and that a session that is already open does not see a new address, and how to start a new one" "end the session with ./99.cleanup_DELETE.sh"
STUB_STATUS_GET=404 STUB_STATUS_POST=201 urun ../06-sharing-a-folder/02.folder_POST.sh
expect "02: looks for the folder, creates it, uploads the file" "$(ucalls | tr '\n' ' ')" "GET ${F}?metadata=true POST ${F} POST ${F} "
has "02: the file is named notes.txt" "filename=notes.txt"
STUB_STATUS_POST=201 urun ../06-sharing-a-folder/02.folder_POST.sh
expect "02: a folder that is there is used as it is: only the upload" "$(ucalls | tr '\n' ' ')" "GET ${F}?metadata=true POST ${F} "
urun ../06-sharing-a-folder/03.folder_PATCH_share.sh
expect "03: with no e-mail address it prints the usage, exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "03: the usage names the parameters" "Usage: ./03.folder_PATCH_share.sh EMAIL [RIGHTS]"
has "03: and what RIGHTS can be" "read (1), write (3: read and upload) or full (7: read, upload and delete)"
urun ../06-sharing-a-folder/03.folder_PATCH_share.sh guest@example.com bogus
expect "03: RIGHTS that is not one of them is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/03.folder_PATCH_share.sh guest@example.com
expect "03: PATCH of the folder" "$(ucalls)" "PATCH ${F}"
expect "03: adds the sharing, read only by default, with the user, no e-mail sent" "$(payload 1 | jq -c '[.[0].op, .[0].path, .[0].value.collaborators, .[0].value.shareRights, .[0].value.enableNotifications, .[0].value.enableOwnerNotifications]')" \
  '["add","/sharedDirectoryProperties",["guest@example.com"],1,false,false]'
expect "03: exit 0" "${RC}" "0"
for pair in "read:1" "write:3" "full:7" "1:1" "3:3" "7:7"; do
    STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/03.folder_PATCH_share.sh guest@example.com "${pair%%:*}"
    expect "03: RIGHTS ${pair%%:*} is shareRights ${pair##*:}" "$(payload 1 | jq -r '.[0].value.shareRights')" "${pair##*:}"
done
STUB_STATUS_PATCH=400 urun ../06-sharing-a-folder/03.folder_PATCH_share.sh guest@example.com
expect "03: a 400 is exit 1, with the two likely reasons" "${RC}" "1"
has "03: the hint" "an account with no e-mail address (see 01), or an address the server does not know"
has "03: and the note about the session" "end the session with ./99.cleanup_DELETE.sh"
SHARED=$(body shared_meta '{"self":{"isShared":true,"sharedDirectoryProperties":{"ownerName":"owner","ownerEmail":"owner@example.com","collaborators":["guest@example.com"],"shareRights":3}}}')
GET_BODY="${SHARED}" urun ../06-sharing-a-folder/04.folder_GET_sharing.sh
expect "04: GET of the folder with metadata=true" "$(ucalls)" "GET ${F}?metadata=true"
has "04: who it is shared with" "shared with:   guest@example.com"
has "04: the rights, in words" "rights:        3 (read and upload)"
GET_BODY="$(body unshared_meta '{"self":{"isShared":false}}')" urun ../06-sharing-a-folder/04.folder_GET_sharing.sh
has "04: a folder that is not shared says so" "shared:        false"
urun ../06-sharing-a-folder/05.folder_PATCH_rights.sh
expect "05: with no RIGHTS it prints the usage, exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "05: the usage" "Usage: ./05.folder_PATCH_rights.sh RIGHTS"
urun ../06-sharing-a-folder/05.folder_PATCH_rights.sh nope
expect "05: RIGHTS that is not one of them is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
SEQ="${WORK}/seq06"; rm -rf "${SEQ}"; mkdir -p "${SEQ}"
cp "${WORK}/me.json" "${SEQ}/1.json"
echo '{"self":{"sharedDirectoryProperties":{"shareRights":3}}}' > "${SEQ}/2.json"
STUB_CURL_GET_SEQUENCE="${SEQ}" STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/05.folder_PATCH_rights.sh write
expect "05: replaces the rights, then reads them back" "$(ucalls | tr '\n' ' ')" "PATCH ${F} GET ${F}?metadata=true "
expect "05: the patch" "$(payload 1 | jq -c '[.[0].op,.[0].path,.[0].value]')" '["replace","/sharedDirectoryProperties/shareRights",3]'
expect "05: exit 0" "${RC}" "0"
GET_BODY="${SHARED}" STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/05.folder_PATCH_rights.sh full
expect "05: rights that read back as something else are exit 1" "${RC}" "1"
STUB_STATUS_PATCH=403 urun ../06-sharing-a-folder/05.folder_PATCH_rights.sh read
expect "05: a refused change is exit 1" "${RC}" "1"
has "05: and says to share the folder first" "Run 03.folder_PATCH_share.sh first"
GET_BODY="$(body unshared_after '{"self":{"isShared":false}}')" STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/06.folder_PATCH_unshare.sh
expect "06: PATCH to remove the sharing, then a read" "$(ucalls | tr '\n' ' ')" "PATCH ${F} GET ${F}?metadata=true "
expect "06: the patch removes /sharedDirectoryProperties" "$(payload 1 | jq -c '[.[0].op, .[0].path]')" '["remove","/sharedDirectoryProperties"]'
expect "06: exit 0" "${RC}" "0"
GET_BODY="${SHARED}" STUB_STATUS_PATCH=204 urun ../06-sharing-a-folder/06.folder_PATCH_unshare.sh
expect "06: a folder that is still shared afterwards is exit 1" "${RC}" "1"
STUB_STATUS_DELETE=204 urun ../06-sharing-a-folder/07.folder_DELETE.sh
expect "07: deletes the file, then the folder" "$(ucalls | tr '\n' ' ')" "DELETE ${F}/notes.txt DELETE ${F} "
STUB_STATUS_DELETE=403 urun ../06-sharing-a-folder/07.folder_DELETE.sh
expect "07: a refusal stops it after the first (exit 1)" "${RC}:$(ucalls | grep -c DELETE)" "1:1"
urun ../06-sharing-a-folder/99.cleanup_DELETE.sh
expect "99: unshares, deletes the file and the folder by name, then logs out" "$(calls | tr '\n' ' ')" "PATCH ${F} DELETE ${F}/notes.txt DELETE ${F} DELETE ${BASE}/myself "
expect "99: the unshare is a JSON Patch that removes /sharedDirectoryProperties" "$(payload 1 | jq -c .)" '[{"op":"remove","path":"/sharedDirectoryProperties"}]'
expect "99: and it is sent as JSON, with the Referer header" "$(headers | grep -cE '^(Content-Type: application/json|Referer: .+)$')" "$(( $(ncalls) + 1 ))"
urun ../06-sharing-a-folder/00.run_all.sh
expect "00: with no e-mail address it stops at once: exit 2, no call at all (not even the login), no cleanup" "${RC}:$(ncalls)" "2:0"
has "00: with the usage" "Usage: ./00.run_all.sh EMAIL [RIGHTS]"
has "00: and the reason it asks first" "it is asked for before anything is created"
urun ../06-sharing-a-folder/00.run_all.sh guest@example.com bogus
expect "00: RIGHTS that is not valid stops it at once too (exit 2, no call)" "${RC}:$(ncalls)" "2:0"
urun ../06-sharing-a-folder/00.run_all.sh guest@example.com write
expect "00: with an account that may not share it stops at 01, and still cleans up" "${RC}" "1"
has "00: says which step failed" "01.sharing_GET_myself failed."
has "00: and cleans up" "Cleaned up."
GET_BODY="${ALLOWED}" STUB_STATUS_POST=201 STUB_STATUS_PATCH=204 STUB_STATUS_DELETE=204 urun ../06-sharing-a-folder/00.run_all.sh guest@example.com full
has "00: shows each step with its arguments: the share with the e-mail and the rights asked for" "=== 03.folder_PATCH_share guest@example.com full ==="
has "00: and goes on to try the type of share write" "=== 05.folder_PATCH_rights write ===" 

echo "=== 07-secret-questions ==="
SQ="../07-secret-questions"
uc 07-secret-questions
QL=$(body qlist '["First question?","Second question?"]')
GET_BODY="${QL}" urun ${SQ}/01.secretQuestions_GET.sh
expect "01: GET /secretQuestions" "$(ucalls)" "GET ${BASE}/secretQuestions"
has "01: the questions, numbered" "  2  Second question?"
expect "01: exit 0" "${RC}" "0"
STATUS_GET=503 urun ${SQ}/01.secretQuestions_GET.sh
expect "01: a service that is switched off (503) is exit 3" "${RC}" "3"
has "01: and it says who must switch it on, and what" "An administrator must switch it on: the server option Users.SecretQuestion.Enabled has to be true."
STUB_STATUS_GET=500 urun ${SQ}/01.secretQuestions_GET.sh
expect "01: any other refusal is exit 1" "${RC}" "1"
GET_BODY="$(body mine '{"secretQuestion":"First question?"}')" urun ${SQ}/02.secretQuestion_GET_mine.sh
expect "02: GET /myself/secretQuestion" "$(ucalls)" "GET ${BASE}/myself/secretQuestion"
has "02: prints it" "The secret question of apiadmin: First question?"
STATUS_GET=503 urun ${SQ}/02.secretQuestion_GET_mine.sh
expect "02: a 503 with the list refused too is a service that is switched off: exit 3" "${RC}" "3"
SEQ7="${WORK}/seq07"; rm -rf "${SEQ7}"; mkdir -p "${SEQ7}"; cp "${WORK}/me.json" "${SEQ7}/1.json"; echo '{}' > "${SEQ7}/2.json"; cp "${QL}" "${SEQ7}/3.json"
STUB_CURL_GET_SEQUENCE="${SEQ7}" STUB_STATUS_GET_SEQ="200 503 200" STUB_COUNTER="${WORK}/ctr07" urun ${SQ}/02.secretQuestion_GET_mine.sh
rm -f "${WORK}"/ctr07.*
expect "02: a 503 for the question and a 200 for the list is a service that is on with no question: exit 4, and the list was asked" "${RC}:$(ucalls | tr '\n' ' ')" "4:GET ${BASE}/myself/secretQuestion GET ${BASE}/secretQuestions "
has "02: says so" "has no secret question yet"
FORCED=$(body forced '{"errors":[{"code":"error.secretQuestion.required","detail":"You have to set a new secret question."}]}')
rm -f "${UC}/session.cookie.jar"
STUB_STATUS_POST=403 STUB_CURL_POST_BODY="${FORCED}" run ${SQ}/02.secretQuestion_GET_mine.sh
expect "02: a login the server refuses because a new question was asked for is exit 5, with the way out, and no jar is left" "${RC}:$([ -e "${UC}/session.cookie.jar" ] && echo jar || echo none)" "5:none"
has "02: the message says who asked, and that everything else is refused until then" "An administrator has asked apiadmin to choose a new secret question, and the server refuses everything else until it does."
has "02: and names the script that needs no session" "07-secret-questions/03.secretQuestion_PUT.sh ANSWER [QUESTION_NUMBER]"
STUB_STATUS_POST=403 run ${SQ}/02.secretQuestion_GET_mine.sh
expect "02: any other refused login is exit 1" "${RC}" "1"
GET_BODY="${FORCED}" STUB_STATUS_GET=403 urun ${SQ}/02.secretQuestion_GET_mine.sh
expect "02: when an administrator asked for a new question it is exit 5" "${RC}" "5"
has "02: and says to choose one with 03" "Choose one with ./03.secretQuestion_PUT.sh ANSWER [QUESTION_NUMBER]"
urun ${SQ}/03.secretQuestion_PUT.sh
expect "03: with no ANSWER it prints the usage like the other scripts: exit 2, no call" "${RC}:$(ncalls)" "2:0"
has "03: the usage" "Usage: ./03.secretQuestion_PUT.sh ANSWER [QUESTION_NUMBER]"
has "03: what each parameter is" "ANSWER           the answer to the secret question"
has "03: and that it changes the account and can only be replaced" "a secret question cannot be cleared once it is set: it can only be replaced"
urun ${SQ}/03.secretQuestion_PUT.sh Rex 0
expect "03: a number that is not a number above 0 is exit 2, no call" "${RC}:$(ncalls)" "2:0"
GET_BODY="${QL}" STUB_STATUS_PUT=204 urun ${SQ}/03.secretQuestion_PUT.sh Rex
expect "03: lists the questions, then PUTs the first: no session, so no check of one" "$(calls | tr '\n' ' ')" "GET ${BASE}/secretQuestions PUT ${BASE}/myself/secretQuestion "
has "03: and both calls carry the user and password (Basic), because a session cannot be had by an account that has to choose a new question" "BASIC_AUTH: apiadmin:s3cret"
expect "03: neither sends the session cookie" "$(printf '%s\n' "${OUT}" | grep -c '^COOKIE:')" "0"
expect "03: the body has the password, the question picked from the list and the answer given" "$(payload 1 | jq -c '[.password,.secretQuestion,.secretAnswer]')" '["s3cret","First question?","Rex"]'
expect "03: exit 0" "${RC}" "0"
GET_BODY="${QL}" STUB_STATUS_PUT=204 urun ${SQ}/03.secretQuestion_PUT.sh "an answer with spaces" 2
expect "03: the second parameter picks the question, and the answer may hold spaces" "$(payload 1 | jq -c '[.secretQuestion,.secretAnswer]')" '["Second question?","an answer with spaces"]'
GET_BODY="${QL}" urun ${SQ}/03.secretQuestion_PUT.sh Rex 3
expect "03: a number past the list is exit 2, and nothing is PUT" "${RC}:$(calls | grep -c PUT)" "2:0"
GET_BODY="${QL}" STUB_STATUS_PUT=400 urun ${SQ}/03.secretQuestion_PUT.sh Rex
expect "03: a refused change is exit 1" "${RC}" "1"
STATUS_GET=503 urun ${SQ}/03.secretQuestion_PUT.sh Rex
expect "03: a service that is switched off is exit 3" "${RC}" "3"
SEQ7B="${WORK}/seq07b"; rm -rf "${SEQ7B}"; mkdir -p "${SEQ7B}"; cp "${WORK}/me.json" "${SEQ7B}/1.json"; cp "${QL}" "${SEQ7B}/2.json"; echo '{"secretQuestion":"First question?"}' > "${SEQ7B}/3.json"
STUB_CURL_GET_SEQUENCE="${SEQ7B}" urun ${SQ}/04.secretQuestion_GET_back.sh
expect "04: reads the list and the account's question" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/secretQuestions GET ${BASE}/myself/secretQuestion "
has "04: and says it is the one picked (number 1 by default)" "It is question number 1 of the list."
expect "04: exit 0" "${RC}" "0"
STUB_CURL_GET_SEQUENCE="${SEQ7B}" urun ${SQ}/04.secretQuestion_GET_back.sh 2
expect "04: another question than the number given is exit 1" "${RC}" "1"
urun ${SQ}/04.secretQuestion_GET_back.sh x
expect "04: a number that is not a number is exit 2, with the usage, no call" "${RC}:$(ncalls)" "2:0"
ERR=$(body sq_err '{"errors":[{"code":"error.secretQuestion.notFound","detail":"Secret question not valid."}]}')
GET_BODY="${QL}" STUB_STATUS_PUT=400 STUB_BODY_OTHER="${ERR}" urun ${SQ}/05.secretQuestion_PUT_refused.sh
expect "05: the list, then three PUTs" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/secretQuestions PUT ${BASE}/myself/secretQuestion PUT ${BASE}/myself/secretQuestion PUT ${BASE}/myself/secretQuestion "
expect "05: an unlisted question, a wrong password, an empty answer" "$(payload 1 | jq -r .secretQuestion):$(payload 2 | jq -r .password):$(payload 3 | jq -r '.secretAnswer|length')" "Is this question on the list?:not-the-password:0"
has "05: shows the error code of the server" "error.secretQuestion.notFound"
expect "05: all three refused: exit 0" "${RC}" "0"
GET_BODY="${QL}" STUB_STATUS_PUT=204 urun ${SQ}/05.secretQuestion_PUT_refused.sh
expect "05: an attempt that is accepted is a failure (exit 1)" "${RC}" "1"
urun ${SQ}/99.cleanup_DELETE.sh
expect "99: only the logout" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/myself "
urun ${SQ}/00.run_all.sh
expect "00: with no answer and no question it stops at once: exit 2, no call at all (not even the login)" "${RC}:$(ncalls)" "2:0"
has "00: with the usage" "Usage: ./00.run_all.sh ANSWER QUESTION_NUMBER"
urun ${SQ}/00.run_all.sh Rex
expect "00: the answer without the number of the question is exit 2 too, no call" "${RC}:$(ncalls)" "2:0"
urun ${SQ}/00.run_all.sh "" 2
expect "00: the number without the answer is exit 2 too, no call" "${RC}:$(ncalls)" "2:0"
urun ${SQ}/00.run_all.sh Rex abc
expect "00: a number that is not a number is exit 2, no call" "${RC}:$(ncalls)" "2:0"
STATUS_GET=503 urun ${SQ}/00.run_all.sh Rex 1
expect "00: with a service that is switched off it stops before any step (exit 3), says who must switch it on, and drops the session" "${RC}:$(calls | tail -1)" "3:DELETE ${BASE}/myself"
has "00: the reason" "An administrator must switch it on"
has "00: and the cleanup" "Cleaned up."
GET_BODY="${QL}" urun ${SQ}/00.run_all.sh Rex 10
expect "00: a number past the questions the server offers (10, it offers 2) is exit 2, before any step" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== 0[1-5]')" "2:0"
has "00: says how many there are" "There is no question number 10: the server offers 2 (1 to 2)."
expect "00: it asked for the list once, changed nothing, and ended the session at once" "$(calls | tr '\n' ' ')" "GET ${BASE}/myself GET ${BASE}/secretQuestions DELETE ${BASE}/myself "
expect "00: the session is gone" "$([ -e "${UC}/session.cookie.jar" ] && echo jar || echo none)" "none"
GET_BODY="${QL}" urun ${SQ}/00.run_all.sh Rex 3
expect "00: one past the end (3 of 2) is refused too" "${RC}" "2"
GET_BODY="${QL}" STUB_STATUS_PUT=204 urun ${SQ}/00.run_all.sh Rex 2
expect "00: the last question (2 of 2) is accepted: the steps run" "$(printf '%s\n' "${OUT}" | grep -c '^=== 03.secretQuestion_PUT Rex 2')" "1"
GET_BODY="${QL}" STUB_STATUS_PUT=204 urun ${SQ}/00.run_all.sh Rex 2
has "00: with an answer and a number it passes them to 03" "=== 03.secretQuestion_PUT Rex 2 ==="
has "00: and the number to 04" "=== 04.secretQuestion_GET_back 2 ==="

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
