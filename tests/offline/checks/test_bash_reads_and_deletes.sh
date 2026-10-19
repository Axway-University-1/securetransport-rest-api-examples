#!/bin/bash
# ==============================================================================
# Run the examples that read, look up and delete against a stub curl, and the
# EndUser examples that open their own session, and check the calls they make.
#
# test_bash_payloads.sh checks what the create examples send. This one checks
# the rest: that a DELETE goes to the id the lookup found and to nothing when
# the lookup finds nothing, that a count is read from totalCount, and that an
# EndUser call carries the csrfToken its login returned.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_reads_and_deletes"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin/sub" "${WORK}/eu/sub"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"

# The Admin examples find set_variables.local.sh one directory above themselves
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.local.sh"
# The EndUser scripts build ST_URL from these values themselves
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/eu/set_variables.local.sh"

BASE="https://st.example.com:8444/api/v2.0"
LOOKUP="${TESTS_DIR}/fixtures/lookup_result.json"
EMPTY="${WORK}/empty.json"
echo '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}' > "${EMPTY}"

# run TREE RELATIVE_PATH [ARGS...]
#   Runs one example with the stub curl. GET_BODY, POST_BODY, STATUS, PRINT_CODE
#   and CSRF set what the stub answers. Sets OUT and RC.
run() {
    local tree="$1" rel="$2" src base
    shift 2
    if [ "${tree}" = "admin" ]; then src="${REPO}/Admin/API 2.0/bash/${rel}"; else src="${REPO}/EndUser/API 2.0/bash/${rel}"; fi
    base=$(basename "${rel}")
    cp "${src}" "${WORK}/${tree}/sub/${base}"
    OUT=$(cd "${WORK}/${tree}/sub" && PATH="${WORK}/bin:${PATH}" \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" \
          STUB_CURL_STATUS="${STATUS:-201}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE="${PRINT_CODE:-}" \
          STUB_CURL_CSRF="${CSRF:-}" bash "./${base}" "$@" 2>&1)
    RC=$?
}
# Every call as "METHOD URL", in order. A URL may hold spaces (an unencoded
# date), so the whole rest of the line is the URL.
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
count_calls() { calls | grep -cF -- "$1"; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }

echo "=== 06.TransferSites ==="

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "06.TransferSites/03.sites_GET.sh"
expect "sites GET: two calls" "$(calls)" "GET ${BASE}/sites?account=john
GET ${BASE}/sites?account=john&protocol=ssh"
has "sites GET: one line per SSH site" "obj-1  SSH_PULL  st.example.com:8022  /outbound-drop"

# 06.TransferSites/04.sites_id_DELETE.sh checks the status of every call now: test_bash_admin_sweep_a.sh covers it
echo
echo "=== 07.Subscriptions ==="

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "07.Subscriptions/01.subscriptions_GET.sh"
expect "subscriptions GET: filters by account, then by type" "$(calls)" "GET ${BASE}/subscriptions?account=john
GET ${BASE}/subscriptions?account=john&type=AdvancedRouting"
has "subscriptions GET: one line per subscription" "obj-1  /inbox  AdvancedRoutingApplication"

# 07.Subscriptions/04.subscriptions_id_DELETE.sh checks the status of every call now: test_bash_admin_sweep_a.sh covers it

echo
echo "=== 09.CompositeRoutes ==="

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "09.CompositeRoutes/06.routes_GET.sh"
has "routes GET: one line per composite route of the account" "obj-1  SSH_PULL  template=tpl-1  subscriptions=sub-1"
has "routes GET: the steps of the simple route" "  Compress  ENABLED"
expect "routes GET: reads the simple route by the id it found" "$(count_calls "GET ${BASE}/routes/obj-1")" "1"

# 09.CompositeRoutes/07.routes_id_DELETE.sh checks the status of every call now: test_bash_admin_sweep_a.sh covers it

echo
echo "=== 16.TransferLogs ==="

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "16.TransferLogs/01.logs_transfers_GET.sh"
expect "logs GET: the latest 10 of the account, then its failures" "$(calls)" "GET ${BASE}/logs/transfers?account=john&sortByStartTime=descending&limit=10
GET ${BASE}/logs/transfers?account=john&status=Failed&limit=1&fields=id"
has "logs GET: the count is totalCount, not returnCount" "42 transfer(s) of 'john' in the log, in all."
has "logs GET: the failed count too" "42 failed transfer(s)."

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "16.TransferLogs/01.logs_transfers_GET.sh" alice
expect "logs GET: takes the account from the command line" "$(count_calls "account=alice&")" "2"

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "16.TransferLogs/02.logs_transfers_GET_billable.sh" 3 john
expect "billable: one call per day" "$(count_calls "GET ${BASE}/logs/transfers?isBillable=true&account=john&startTimeAfter=")" "3"
RFC='[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} 00:00:00 [+-][0-9]{4}'
expect "billable: each day runs midnight to midnight, in RFC 2822" \
  "$(calls | grep -cE "startTimeAfter=${RFC}&endTimeBefore=${RFC}&limit=1&fields=id$")" "3"
STARTS=$(calls | sed -n 's/.*startTimeAfter=\([^&]*\)&.*/\1/p' | tail -n 2)
ENDS=$(calls | sed -n 's/.*endTimeBefore=\([^&]*\)&.*/\1/p' | head -n 2)
expect "billable: each day ends where the next starts" "${ENDS}" "${STARTS}"
has "billable: adds up totalCount, not returnCount" "Total: 126 billable transfer(s) in 3 day(s)"

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "16.TransferLogs/02.logs_transfers_GET_billable.sh"
expect "billable: 7 days by default" "$(count_calls "isBillable=true")" "7"
expect "billable: no account filter unless one is given" "$(count_calls "account=")" "0"
has "billable: says it counts every account" "Billable transfers per day, for every account"

STATUS=200 PRINT_CODE=1 GET_BODY="${LOOKUP}" run admin "16.TransferLogs/02.logs_transfers_GET_billable.sh" x
expect "billable: refuses a DAYS that is not a number" "${RC}:$(count_calls "GET")" "2:0"

echo
echo "=== EndUser 02.Files ==="

# These two use the shared session like every other EndUser example: the helper, the login script it runs when there is
# no session, and a jar, as 01.Authenticate/01.myself_POST.sh leaves it (the stub writes none)
cp "${REPO}/EndUser/API 2.0/bash/ensure_session.sh" "${WORK}/eu/"
cp -R "${REPO}/EndUser/API 2.0/bash/01.Authenticate" "${WORK}/eu/"
touch "${WORK}/eu/myCookie.jar"

STATUS=200 STATUS_GET=404 PRINT_CODE=1 run eu "02.Files/02.files_name_POST_folder.sh" "/reports/my folder"
expect "folder: checks the session, looks whether the folder is there, creates it" "$(calls)" "GET ${BASE}/myself
GET ${BASE}/files/reports/my%20folder?metadata=true
POST ${BASE}/files/reports/my%20folder"
expect "folder: created, exit 0" "${RC}" "0"
expect "folder: sends no csrfToken and no login of its own: the session is the shared one" \
  "$(printf '%s\n' "${OUT}" | grep -c 'csrfToken\|BASIC_AUTH')" "0"
FOLDER_BODY=$(payload 1)
expect "folder: the body says it is a directory, and holds no name" \
  "$(printf '%s' "${FOLDER_BODY}" | jq -c '[.isDirectory, .isRegularFile, has("name")]')" "[true,false,false]"

rm -f "${WORK}/eu/myCookie.jar"
STATUS=401 PRINT_CODE=1 run eu "02.Files/02.files_name_POST_folder.sh"
expect "folder: with no session it logs in first, and stops when the login fails" "${RC}:$(count_calls "/files")" "1:0"
touch "${WORK}/eu/myCookie.jar"

STATUS=200 STATUS_GET=200 PRINT_CODE=1 run eu "02.Files/02.files_name_POST_folder.sh" "reports"
expect "folder: one that is already there is not created again: it says so and exits 0" \
  "${RC}:$(calls | cut -d' ' -f1 | tr '\n' ' ')" "0:GET GET "
has "folder: and the message is plain, not the server's 'creating file: null'" "The folder 'reports' already exists. Nothing to create."
# only the create is refused: a wrapper answers 409 for the POST of /files/ and passes everything else to the stub
mkdir -p "${WORK}/bin_409"
printf '#!/bin/bash\nif [[ "$*" == *"-X POST"* && "$*" == */files/* ]]; then printf "{}\\nHTTP 409\\n"; echo "METHOD: POST" >&2; echo "URL: refused" >&2; exit 0; fi\nexec "%s/bin/curl" "$@"\n' "${WORK}" > "${WORK}/bin_409/curl"
chmod +x "${WORK}/bin_409/curl"
OUT=$(cd "${WORK}/eu/sub" && PATH="${WORK}/bin_409:${WORK}/bin:${PATH}" STUB_CURL_STATUS=200 STUB_CURL_STATUS_GET=404 STUB_CURL_PRINT_CODE=1 bash ./02.files_name_POST_folder.sh reports 2>&1)
RC=$?
expect "folder: a refused create (409) exits 1" "${RC}" "1"
has "folder: with the HTTP code" "HTTP 409"

UPLOAD_FILE="${WORK}/upload.txt"
printf 'hello upload' > "${UPLOAD_FILE}"
OPERATION="${WORK}/operation.json"
echo '{"id":"op-1"}' > "${OPERATION}"

STATUS=200 PRINT_CODE=1 POST_BODY="${OPERATION}" run eu "02.Files/08.fileOperations_POST_upload.sh" "${UPLOAD_FILE}" "/inbox/"
expect "upload: checks the session, declares, sends" "$(calls)" "GET ${BASE}/myself
POST ${BASE}/fileOperations
PUT ${BASE}/fileOperations/op-1"
expect "upload: declares the path on the server, in binary" \
  "$(payload 1 | jq -c '[.operation, .filePath, .customAttributes.transferMode]')" '["Upload","/inbox/upload.txt","BINARY"]'
expect "upload: sends the file's content" "$(payload 2)" "hello upload"
has "upload: sends it as octet-stream" "HEADER: Content-Type: application/octet-stream"
expect "upload: sends no csrfToken and no login of its own" "$(printf '%s\n' "${OUT}" | grep -c 'csrfToken\|BASIC_AUTH')" "0"
expect "upload: succeeds" "${RC}" "0"

STATUS=200 PRINT_CODE=1 POST_BODY="${EMPTY}" run eu "02.Files/08.fileOperations_POST_upload.sh" "${UPLOAD_FILE}"
expect "upload: with no operation id, sends nothing and exits 1" "${RC}:$(count_calls "PUT")" "1:0"
expect "upload: to the home folder when no folder is given" "$(payload 1 | jq -r '.filePath')" "/upload.txt"

STATUS=500 PRINT_CODE=1 POST_BODY="${OPERATION}" run eu "02.Files/08.fileOperations_POST_upload.sh" "${UPLOAD_FILE}"
expect "upload: a content that is refused is exit 1 (it used to end 0 when an id had come back)" "${RC}" "1"

STATUS=200 PRINT_CODE=1 run eu "02.Files/08.fileOperations_POST_upload.sh" "${WORK}/no_such_file.txt"
expect "upload: stops before any call when the file is missing" "${RC}:$(calls | wc -l | tr -d ' ')" "1:0"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_reads_and_deletes: PASS"
else
    echo "test_bash_reads_and_deletes: FAIL"
fi
exit "${FAILED}"
