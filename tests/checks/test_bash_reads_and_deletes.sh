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
REPO="$(cd .. && pwd)"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_reads_and_deletes"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin/sub" "${WORK}/eu/sub"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"

# The Admin examples find set_variables.sh one directory above themselves
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
# The EndUser one derives ST_URL and ST_BASIC_AUTH, so use the real one, with
# the test values as its local file
cp "${REPO}/EndUser/API 2.0/bash/set_variables.sh" "${WORK}/eu/set_variables.sh"
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
          STUB_CURL_STATUS="${STATUS:-201}" STUB_CURL_PRINT_CODE="${PRINT_CODE:-}" \
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

AUTH=$(printf '%s' "apiadmin:s3cret" | base64)

STATUS=200 PRINT_CODE=1 CSRF=tok-1 run eu "02.Files/02.files_name_POST_folder.sh" "/reports/my folder"
expect "folder: logs in, creates the folder, logs out" "$(calls)" "POST ${BASE}/myself
POST ${BASE}/files/reports/my%20folder
DELETE ${BASE}/myself"
has "folder: logs in with the configured user" "HEADER: Authorization: Basic ${AUTH}"
expect "folder: sends the login's csrfToken on both later calls" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: csrfToken: tok-1$')" "2"
FOLDER_BODY=$(payload 1)
expect "folder: the body says it is a directory, and holds no name" \
  "$(printf '%s' "${FOLDER_BODY}" | jq -c '[.isDirectory, .isRegularFile, has("name")]')" "[true,false,false]"

STATUS=401 PRINT_CODE=1 run eu "02.Files/02.files_name_POST_folder.sh"
expect "folder: stops when the login fails" "${RC}:$(count_calls "/files")" "1:0"

UPLOAD_FILE="${WORK}/upload.txt"
printf 'hello upload' > "${UPLOAD_FILE}"
OPERATION="${WORK}/operation.json"
echo '{"id":"op-1"}' > "${OPERATION}"

STATUS=200 PRINT_CODE=1 CSRF=tok-2 POST_BODY="${OPERATION}" run eu "02.Files/08.fileOperations_POST_upload.sh" "${UPLOAD_FILE}" "/inbox/"
expect "upload: logs in, declares, sends, logs out" "$(calls)" "POST ${BASE}/myself
POST ${BASE}/fileOperations
PUT ${BASE}/fileOperations/op-1
DELETE ${BASE}/myself"
expect "upload: declares the path on the server, in binary" \
  "$(payload 1 | jq -c '[.operation, .filePath, .customAttributes.transferMode]')" '["Upload","/inbox/upload.txt","BINARY"]'
expect "upload: sends the file's content" "$(payload 2)" "hello upload"
has "upload: sends it as octet-stream" "HEADER: Content-Type: application/octet-stream"
expect "upload: sends the login's csrfToken on every later call" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: csrfToken: tok-2$')" "3"
expect "upload: succeeds" "${RC}" "0"

STATUS=200 PRINT_CODE=1 CSRF=tok-2 POST_BODY="${EMPTY}" run eu "02.Files/08.fileOperations_POST_upload.sh" "${UPLOAD_FILE}"
expect "upload: with no operation id, sends nothing but still logs out" \
  "${RC}:$(count_calls "PUT"):$(count_calls "DELETE ${BASE}/myself")" "1:0:1"
expect "upload: to the home folder when no folder is given" "$(payload 1 | jq -r '.filePath')" "/upload.txt"

STATUS=200 PRINT_CODE=1 run eu "02.Files/08.fileOperations_POST_upload.sh" "${WORK}/no_such_file.txt"
expect "upload: stops before logging in when the file is missing" "${RC}:$(count_calls "POST")" "1:0"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_reads_and_deletes: PASS"
else
    echo "test_bash_reads_and_deletes: FAIL"
fi
exit "${FAILED}"
