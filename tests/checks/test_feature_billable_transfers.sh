#!/bin/bash
# ==============================================================================
# Run the Features/audit-billable-transfers examples against a stub curl, and
# check what they would send.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
FEATURE="Features/audit-billable-transfers"

WORK="${TESTS_DIR}/output/feature_billable_transfers"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/Features" "${WORK}/Admin/API 2.0/bash"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp -R "${REPO}/Features/lib" "${WORK}/Features/lib"
cp -R "${REPO}/${FEATURE}" "${WORK}/${FEATURE}"
rm -f "${WORK:?}/${FEATURE:?}/settings.local.sh" "${WORK:?}/${FEATURE:?}/settings.local.bat" \
      "${WORK:?}/${FEATURE:?}/state.local.sh" "${WORK:?}/${FEATURE:?}/state.local.bat"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/Admin/API 2.0/bash/set_variables.sh"
RUN="${WORK}/${FEATURE}"

echo "export BT_ACCOUNT_PASSWORD='p@ss w0rd'" > "${RUN}/settings.local.sh"
echo "export BT_WAIT_SECONDS=0" >> "${RUN}/settings.local.sh"
echo "export BT_STEP_PAUSE_SECONDS=0" >> "${RUN}/settings.local.sh"

SERVER_NEW="${WORK}/version_new.json"; echo '{"version":"5.5-20260924"}' > "${SERVER_NEW}"
SERVER_OLD="${WORK}/version_old.json"; echo '{"version":"5.5-20260923"}' > "${SERVER_OLD}"

# A HEAD (does the account exist?) answers HEAD_STATUS when a test sets it, else STATUS like every other call.
run() {
    OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="$2" STUB_CURL_STATUS_HEAD="${HEAD_STATUS:-}" \
          STUB_CURL_POST_BODY="${3:-${SERVER_NEW}}" STUB_CURL_LOCATION_ID="${4:-new-id}" \
          STUB_CURL_STATUS="${5:-201}" STUB_CURL_CSRF="csrf-abc" bash "./$1" "${EXTRA_ARG:-}" 2>&1)
    RC=$?
}
# The same, with a status per method (stub_curl_by_method): run_by_method SCRIPT BODY_FILE VAR=value...
# with STUB_STATUS_GET, _POST, _POST_SEQ, _PUT, _DELETE and so on among the variables. POST_BODY is
# what a POST answers with.
mkdir -p "${WORK}/bin_by_method"
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin_by_method/stub_curl_real" && chmod +x "${WORK}/bin_by_method/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin_by_method/curl" && chmod +x "${WORK}/bin_by_method/curl"
run_by_method() {
    local script="$1" body="$2"
    shift 2
    rm -f "${WORK}/counter."*
    OUT=$(cd "${RUN}" && env PATH="${WORK}/bin_by_method:${PATH}" STUB_COUNTER="${WORK}/counter" STUB_CURL_GET_BODY="${body}" \
          STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_STATUS_HEAD="${HEAD_STATUS:-}" STUB_CURL_LOCATION_ID="new-id" \
          STUB_CURL_CSRF="csrf-abc" "$@" bash "./${script}" 2>&1)
    RC=$?
}
calls() { echo "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL:/ {print m, $2}'; }
payloads() { echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | while read -r b; do echo "$b" | base64 -d; echo; done; }
# Only the payloads of POST calls, in order - needed where POST (JSON) and PUT
# (raw file content) calls are interleaved, since piping raw content through jq
# would choke on it
post_payloads() {
    echo "${OUT}" | awk '/^METHOD:/ {m=$2} /^PAYLOAD_B64:/ {if (m == "POST") print substr($0, 14)}' \
      | while read -r b; do echo "$b" | base64 -d; echo; done
}
# read_into ARRAY_NAME, reading from its own stdin: used as
#   read_into ARRAY_NAME < <(some command)
# never as the end of a pipe - each stage of a pipe is its own subshell in this
# bash (3.2, as macOS ships), so a piped-into function cannot set a variable the
# rest of the script can see. Portable stand-in for mapfile/readarray, which
# this bash does not have either.
read_into() {
    local __name="$1" __line
    eval "${__name}=()"
    while IFS= read -r __line; do
        eval "${__name}+=(\"\${__line}\")"
    done
}

echo "=== 01.accounts_POST.sh ==="
# 404 to the HEAD: no partner exists yet
HEAD_STATUS=404 run 01.accounts_POST.sh "${SERVER_NEW}"
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
ACCOUNTS=$(payloads | jq -r '.name + " " + .homeFolder' | tr '\n' '|')
[ "${ACCOUNTS}" = "btTestAccount /home/btTestAccount|partner_to_pull_from /home/partner_to_pull_from|partner_to_push_to /home/partner_to_push_to|" ] \
    && pass "creates the test account and the two partners, each with its own home folder" || fail "accounts: ${ACCOUNTS}"
[ "$(payloads | jq -s -c '[.[].transfersWebServiceAllowed] | unique')" = "[true]" ] && pass "web service right is on for all three" || fail "transfersWebServiceAllowed"
# 200 to the HEAD: the partners are there already, from another test account's run
HEAD_STATUS=200 run 01.accounts_POST.sh "${SERVER_NEW}" "" "" 201
[ "$(payloads | jq -r .name | tr '\n' ' ')" = "btTestAccount " ] && [ "$(echo "${OUT}" | grep -c 'Reused.')" -eq 2 ] \
    && pass "reuses partners that are already there, and creates only the test account" || fail "with partners: $(payloads | jq -r .name)"

echo
echo "=== 02.sites_POST_pull.sh ==="
run 02.sites_POST_pull.sh "${SERVER_NEW}"
[ "$(calls | grep -c '^POST .*/sites$')" -eq 6 ] && pass "creates six pull sites" || fail "site count: $(calls | grep -c sites)"
read_into SITE_BODIES < <(payloads | jq -c .)
NAMES=$(printf '%s\n' "${SITE_BODIES[@]}" | jq -r .name | tr '\n' ' ')
[ "${NAMES}" = "btTestAccountPullSite1 btTestAccountPullSite2 btTestAccountPullSite3 btTestAccountPullSite4 btTestAccountPullSite5 btTestAccountPullSite6 " ] && pass "named btTestAccountPullSite1 to 6, in order" || fail "names: ${NAMES}"
PATTERNS=$(printf '%s\n' "${SITE_BODIES[@]}" | jq -r .downloadPattern | tr '\n' '|')
[ "${PATTERNS}" = "only_inbound*.txt|inbound_and_one_outbound*.txt|inbound_and_two_outbounds.txt|file_*_for_compress.txt|archive_with_2_files.zip|archive_with_2_files_for_2_partners.zip|" ] \
    && pass "each site's pattern matches only its own scenario's file(s), numbered copies included" || fail "patterns: ${PATTERNS}"
echo "${SITE_BODIES[0]}" | jq -e '.type == "ssh" and .protocol == "ssh"' >/dev/null && pass "SSH sites, with protocol set" || fail "type/protocol"
[ "$(echo "${SITE_BODIES[0]}" | jq -r .port)" = "8022" ] && pass "SSH port 8022" || fail "port"
[ "$(echo "${SITE_BODIES[0]}" | jq -c .usePassword)" = "true" ] && pass "usePassword is a JSON boolean" || fail "usePassword"
[ "$(printf '%s\n' "${SITE_BODIES[@]}" | jq -r '[.account, .userName, .downloadFolder] | join(" ")' | sort -u)" = "btTestAccount partner_to_pull_from /btTestAccount/outbound-drop" ] \
    && pass "the test account's sites log in as partner_to_pull_from, to the test account's drop folder there" || fail "pull sites: ${SITE_BODIES[0]}"

echo
echo "=== 03.sites_POST_push.sh ==="
run 03.sites_POST_push.sh "${SERVER_NEW}"
read_into PUSH_BODIES < <(payloads | jq -c .)
[ "$(echo "${PUSH_BODIES[0]}" | jq -r '[.name, .account, .userName, .uploadFolder] | join(" ")')" = "btTestAccountPushSitePartner1 btTestAccount partner_to_push_to /btTestAccount/delivered-1" ] \
    && pass "push site 1 logs in as partner_to_push_to, delivering to btTestAccount/delivered-1" || fail "push1: ${PUSH_BODIES[0]}"
[ "$(echo "${PUSH_BODIES[1]}" | jq -r '[.name, .account, .userName, .uploadFolder] | join(" ")')" = "btTestAccountPushSitePartner2 btTestAccount partner_to_push_to /btTestAccount/delivered-2" ] \
    && pass "push site 2 logs in as partner_to_push_to, delivering to btTestAccount/delivered-2" || fail "push2: ${PUSH_BODIES[1]}"

echo
echo "=== 04.files_POST_folders.sh ==="
run 04.files_POST_folders.sh "${SERVER_NEW}"
# The End User login must actually carry the real account name and password -
# not rely on a shared-lib variable that was never set for this feature's own
# prefix, which would silently log in as ":" and fail every call after it.
# grep -F, not the first BASIC_AUTH line: the version check's own admin-
# authenticated GET /version always comes first and is a different login.
LOGINS=$(echo "${OUT}" | grep '^BASIC_AUTH:' | sed -n '2,$p' | sed 's/^BASIC_AUTH: //' | tr '\n' '|')
[ "${LOGINS}" = "btTestAccount:p@ss w0rd|partner_to_pull_from:p@ss w0rd|partner_to_push_to:p@ss w0rd|" ] \
    && pass "logs in to the End User API as each of the three accounts in turn, with the real password" \
    || fail "End User logins: ${LOGINS}"
FOLDER_CALLS=$(calls | grep '^POST .*files/' | sed 's#.*/files/##' | tr '\n' ' ')
[ "${FOLDER_CALLS}" = "subscription subscription/s1 subscription/s2 subscription/s3 subscription/s4 subscription/s5 subscription/s6 btTestAccount btTestAccount/outbound-drop btTestAccount btTestAccount/delivered-1 btTestAccount/delivered-2 " ] \
    && pass "the test account's subscription folders, then its folder and drop folder in partner_to_pull_from, then its folder and delivered folders in partner_to_push_to" \
    || fail "folders: ${FOLDER_CALLS}"
FOLDER_BODY=$(payloads | jq -s -c '.[0]')
[ "$(echo "${FOLDER_BODY}" | jq -c .isDirectory)" = "true" ] && pass "each is created as a directory" || fail "folder body: ${FOLDER_BODY}"

FORBIDDEN="${WORK}/forbidden.json"
echo '{"message":"Error validating request","validationErrors":["Error occurred while creating file: null"]}' > "${FORBIDDEN}"
OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${SERVER_NEW}" STUB_CURL_POST_BODY="${FORBIDDEN}" \
      STUB_CURL_STATUS=201 STUB_CURL_STATUS_FILES=403 STUB_CURL_CSRF="csrf-abc" bash "./04.files_POST_folders.sh" 2>&1)
if [[ "${OUT}" == *"HTTP 403"* ]] && [[ "${OUT}" == *"Hint: a 403"* ]] && [[ "${OUT}" == *"another uid"* ]]; then pass "a 403 'Error occurred while creating file' says the home folder probably belongs to another uid"; else fail "no hint for the 403 (output: ${OUT:0:300})"; fi
run 04.files_POST_folders.sh "${SERVER_NEW}"
[[ "${OUT}" != *"Hint:"* ]] && pass "no hint when the folders are created" || fail "a hint without a 403"

echo
echo "=== 05.applications_POST.sh ==="
run 05.applications_POST.sh "${SERVER_NEW}"
B=$(payloads | jq -s -c '.[0]')
[ "$(echo "${B}" | jq -r .type)" = "AdvancedRouting" ] && [ "$(echo "${B}" | jq -r .name)" = "btTestAccountApplication" ] && pass "one AdvancedRouting application" || fail "application: ${B}"

echo
echo "=== 06.routes_POST_template.sh ==="
run 06.routes_POST_template.sh "${SERVER_NEW}" "" tmpl-1
B=$(payloads | jq -s -c '.[0]')
[ "$(echo "${B}" | jq -r .type)" = "TEMPLATE" ] && pass "a TEMPLATE route" || fail "template: ${B}"
grep -q 'BT_ID_TEMPLATE=tmpl-1' "${RUN}/state.local.sh" && pass "the new id is saved" || fail "id not saved"

echo
echo "=== 07.routes_POST_simple.sh ==="
run 07.routes_POST_simple.sh "${SERVER_NEW}"
read_into SIMPLE_BODIES < <(payloads | jq -c .)
[ "${#SIMPLE_BODIES[@]}" -eq 5 ] && pass "creates five simple routes" || fail "count: ${#SIMPLE_BODIES[@]}"

S2="${SIMPLE_BODIES[0]}"; S3="${SIMPLE_BODIES[1]}"; S4="${SIMPLE_BODIES[2]}"; S5="${SIMPLE_BODIES[3]}"; S6="${SIMPLE_BODIES[4]}"

[ "$(echo "${S2}" | jq -r '.name')" = "btTestAccountSimpleRoute2" ] && [ "$(echo "${S2}" | jq -r '.steps | length')" = "1" ] \
    && [ "$(echo "${S2}" | jq -r '.steps[0].type')" = "SendToPartner" ] \
    && [ "$(echo "${S2}" | jq -r '.steps[0].transferSiteExpression')" = "btTestAccountPushSitePartner1#!#CVD#!#" ] \
    && pass "2.2: one SendToPartner step, to partner 1" || fail "2.2: ${S2}"

[ "$(echo "${S3}" | jq -r '.steps | length')" = "2" ] \
    && [ "$(echo "${S3}" | jq -r '[.steps[].type] | unique[0]')" = "SendToPartner" ] \
    && [ "$(echo "${S3}" | jq -r '[.steps[].usePrecedingStepFiles] | unique | length')" = "1" ] \
    && [ "$(echo "${S3}" | jq -r '.steps[0].usePrecedingStepFiles')" = "false" ] \
    && [ "$(echo "${S3}" | jq -r '[.steps[].transferSiteExpression] | unique | length')" = "1" ] \
    && pass "2.3: two SendToPartner steps, both reading the route's own input, both to partner 1" || fail "2.3: ${S3}"

[ "$(echo "${S4}" | jq -r '.steps[0].type')" = "Compress" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[0].singleArchiveEnabled')" = "true" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[0].singleArchiveName')" = "files_1_and_2_compressed.zip" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[0].compressionType')" = "ZIP" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[0] | has("postTransformationActionRenameAsExpression")')" = "false" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[1].type')" = "SendToPartner" ] \
    && [ "$(echo "${S4}" | jq -r '.steps[1].usePrecedingStepFiles')" = "true" ] \
    && pass "2.4: Compress into one named archive (not the rename field), then push reading its output" || fail "2.4: ${S4}"

[ "$(echo "${S5}" | jq -r '.steps[0].type')" = "Decompress" ] \
    && [ "$(echo "${S5}" | jq -r '.steps[0].filenameCollisionResolutionType')" = "OVERWRITE" ] \
    && [ "$(echo "${S5}" | jq -r '.steps[0] | has("postTransformationActionRenameAsExpression")')" = "false" ] \
    && [ "$(echo "${S5}" | jq -r '.steps[1].type')" = "SendToPartner" ] \
    && [ "$(echo "${S5}" | jq -r '.steps[1].usePrecedingStepFiles')" = "true" ] \
    && [ "$(echo "${S5}" | jq -r '.steps[1].transferSiteExpression')" = "btTestAccountPushSitePartner1#!#CVD#!#" ] \
    && pass "2.5: Decompress, no rename field, then push both files to partner 1" || fail "2.5: ${S5}"

[ "$(echo "${S6}" | jq -r '.steps | length')" = "3" ] \
    && [ "$(echo "${S6}" | jq -r '.steps[0].type')" = "Decompress" ] \
    && [ "$(echo "${S6}" | jq -r '.steps[1].transferSiteExpression')" = "btTestAccountPushSitePartner1#!#CVD#!#" ] \
    && [ "$(echo "${S6}" | jq -r '.steps[2].transferSiteExpression')" = "btTestAccountPushSitePartner2#!#CVD#!#" ] \
    && [ "$(echo "${S6}" | jq -r '[.steps[1].usePrecedingStepFiles, .steps[2].usePrecedingStepFiles] | unique[0]')" = "true" ] \
    && pass "2.6: Decompress, then push to partner 1, then push to partner 2" || fail "2.6: ${S6}"

echo
echo "=== 08.subscriptions_POST.sh ==="
run 08.subscriptions_POST.sh "${SERVER_NEW}"
read_into SUB_BODIES < <(payloads | jq -c .)
[ "${#SUB_BODIES[@]}" -eq 6 ] && pass "creates six subscriptions" || fail "count: ${#SUB_BODIES[@]}"
FOLDERS=$(printf '%s\n' "${SUB_BODIES[@]}" | jq -r .folder | tr '\n' ' ')
[ "${FOLDERS}" = "/subscription/s1 /subscription/s2 /subscription/s3 /subscription/s4 /subscription/s5 /subscription/s6 " ] \
    && pass "one subscription per scenario folder" || fail "folders: ${FOLDERS}"
for i in 0 1 2 4 5; do
    echo "${SUB_BODIES[$i]}" | jq -e 'has("createFilesList") | not' >/dev/null \
        && pass "scenario s$((i+1)): no batching trigger" || fail "scenario s$((i+1)) unexpectedly has createFilesList"
done
S4SUB="${SUB_BODIES[3]}"
[ "$(echo "${S4SUB}" | jq -r .createFilesList.createFilesListEnabled)" = "true" ] && pass "scenario s4: batches its two files with a trigger file" || fail "s4 createFilesList: ${S4SUB}"
[ "$(echo "${S4SUB}" | jq -r .postTransmissionActions.submitFilterType)" = "TRIGGER_FILE_CONTENT" ] && pass "s4: submits the files read from the trigger file" || fail "s4 submitFilterType"
COND=$(echo "${S4SUB}" | jq -r .postTransmissionActions.triggerOnConditionExpression)
EXPECT_COND="\${stenv['target'].matches('.*\\\\.trigger')?1:0}"
[ "${COND}" = "${EXPECT_COND}" ] && pass "s4: the trigger condition keeps its two backslashes" || fail "s4 condition: ${COND}"

echo
echo "=== 09.routes_POST_composite.sh ==="
# Needs the ids from 06, 07, 08 - already saved in state.local.sh by the runs above
run 09.routes_POST_composite.sh "${SERVER_NEW}"
read_into COMP_BODIES < <(payloads | jq -c .)
[ "${#COMP_BODIES[@]}" -eq 5 ] && pass "creates five composite routes" || fail "count: ${#COMP_BODIES[@]}"
echo "${COMP_BODIES[0]}" | jq -e '.routeTemplate == "tmpl-1" and (.subscriptions | length) == 1' >/dev/null \
    && pass "each is built from the template and attached to one subscription" || fail "composite 2: ${COMP_BODIES[0]}"
echo "${COMP_BODIES[0]}" | jq -e '.steps[0].type == "ExecuteRoute"' >/dev/null \
    && pass "each runs its own simple route" || fail "composite 2 steps: ${COMP_BODIES[0]}"

echo
echo "=== 10.files_upload_POST.sh ==="
echo '{"id":"op-7"}' > "${WORK}/operation.json"
run 10.files_upload_POST.sh "${SERVER_NEW}" "${WORK}/operation.json"
[ "$(calls | grep -c '^POST .*fileOperations$')" -eq 7 ] && pass "declares seven uploads: 5 files + 2 archives" || fail "declares: $(calls | grep -c fileOperations)"
[ "$(calls | grep -c '^PUT .*fileOperations/op-7$')" -eq 7 ] && pass "sends seven contents, with PUT" || fail "puts: $(calls | grep -c PUT)"
DECLARE_PATHS=$(post_payloads | jq -r 'select(.operation=="Upload") | .filePath' | tr '\n' ' ')
[ "${DECLARE_PATHS}" = "/btTestAccount/outbound-drop/only_inbound.txt /btTestAccount/outbound-drop/inbound_and_one_outbound.txt /btTestAccount/outbound-drop/inbound_and_two_outbounds.txt /btTestAccount/outbound-drop/file_1_for_compress.txt /btTestAccount/outbound-drop/file_2_for_compress.txt /btTestAccount/outbound-drop/archive_with_2_files.zip /btTestAccount/outbound-drop/archive_with_2_files_for_2_partners.zip " ] \
    && pass "uploads all five files then both archives, into the test account's drop folder" || fail "paths: ${DECLARE_PATHS}"
[ "$(echo "${OUT}" | grep '^BASIC_AUTH:' | sed -n 2p)" = "BASIC_AUTH: partner_to_pull_from:p@ss w0rd" ] \
    && pass "uploads as partner_to_pull_from, so the uploads count against it, not the test account" || fail "upload login: $(echo "${OUT}" | grep '^BASIC_AUTH:' | sed -n 2p)"
# The archive content itself: a real zip, with its two member names inside
ZIP_CONTENT=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | tail -n 1 | base64 -d)
echo "${ZIP_CONTENT}" | head -c4 | grep -q "PK" && pass "the last upload is a real zip (PK signature)" || fail "not a zip"
printf '%s' "${ZIP_CONTENT}" | strings | grep -q "file_1_inside_archive_for_2_partners.txt" \
    && pass "the archive contains its named member file" || fail "member name not found in zip bytes"

echo
echo "=== 11.transfers_pull_POST.sh ==="
run 11.transfers_pull_POST.sh "${SERVER_NEW}" "" "" 202
[ "$(calls | grep -c '^POST .*transfers/operations?operation=pull$')" -eq 6 ] && pass "runs all six pulls" || fail "pulls: $(calls | grep -c pull)"
read_into PULL_BODIES < <(payloads | jq -c .)
[ "$(echo "${PULL_BODIES[0]}" | jq -r .site)" = "btTestAccountPullSite1" ] && [ "$(echo "${PULL_BODIES[0]}" | jq -r .destinationDirectory)" = "/subscription/s1" ] \
    && pass "each pull uses its own site into its own scenario folder" || fail "pull 1: ${PULL_BODIES[0]}"

echo
echo "=== billable_GET_report.sh ==="
# returnCount (1, as if limit=1 capped the page) and totalCount (4, the real
# total) deliberately differ, so this catches a regression back to reading
# returnCount - the exact bug confirmed against a real server: every day's
# count was silently capped at 1 by the page size, not the true total.
cat > "${WORK}/report.json" <<JSON
{"version": "5.5-20260924", "resultSet": {"returnCount": 1, "totalCount": 4}}
JSON
OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/report.json" STUB_CURL_CSRF="csrf-abc" bash ./billable_GET_report.sh before 2>&1)
RC=$?
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
[[ "${OUT}" == *"(before)"* ]] && pass "the label is printed in the heading" || fail "heading: $(echo "${OUT}" | grep Billable)"
DAY_LINES=$(echo "${OUT}" | grep -cE '^  [0-9]{4}-[0-9]{2}-[0-9]{2} +4 +4 +4$')
[ "${DAY_LINES}" -eq 7 ] && pass "reports seven days, one column per account, using totalCount (4), not returnCount (1)" || fail "day lines: ${DAY_LINES}"
[ "$(echo "${OUT}" | grep '^TODAY_COUNT' | tr '\n' '|')" = "TODAY_COUNT partner_to_pull_from: 4|TODAY_COUNT btTestAccount: 4|TODAY_COUNT partner_to_push_to: 4|" ] \
    && pass "prints a machine-readable TODAY_COUNT line per account, for 00.run_all.sh to diff" || fail "TODAY_COUNT lines: $(echo "${OUT}" | grep TODAY_COUNT)"
# Full lines, not calls() (which splits on whitespace via awk): the stub does
# not URL-encode the RFC 2822 dates, so the URL itself contains spaces
REPORT_URLS=$(echo "${OUT}" | grep '^URL: ' | sed 's#^URL: ##; s#.*logs/transfers?##')
[ "$(echo "${REPORT_URLS}" | grep -c 'isBillable=true')" -eq 21 ] && pass "every query filters isBillable=true: 7 days, 3 accounts" || fail "isBillable missing"
for a in partner_to_pull_from btTestAccount partner_to_push_to; do
    [ "$(echo "${REPORT_URLS}" | grep -c "&account=${a}&")" -eq 7 ] && pass "seven days scoped to ${a}, with account=" || fail "account=${a}: $(echo "${REPORT_URLS}" | grep -c "account=${a}")"
done
# accountName= is ignored by /logs/transfers, which then counts every account:
# the bug this report once had
echo "${REPORT_URLS}" | grep -q 'accountName=' && fail "a query uses accountName=, which the endpoint ignores" || pass "no query uses accountName=, which the endpoint ignores"
# A count the server did not give (a refused call has no resultSet): shown as ?, and the exit code says so
echo '{"version":"5.5-20260924","message":"Error validating request"}' > "${WORK}/report_refused.json"
OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/report_refused.json" STUB_CURL_CSRF="csrf-abc" bash ./billable_GET_report.sh before 2>&1)
RC=$?
[ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Some counts could not be read"* ]] && [ "$(echo "${OUT}" | grep -cE '^  [0-9]{4}-[0-9]{2}-[0-9]{2} +\? +\? +\?$')" -eq 7 ] \
    && pass "counts that could not be read: shown as ?, said so, and exit 1" || fail "unreadable counts: exit ${RC}"
STARTS=$(echo "${REPORT_URLS}" | sed -n 's/.*startTimeAfter=\([A-Za-z]*, [0-9]* [A-Za-z]* [0-9]*\).*/\1/p' | sort -u)
[ "$(echo "${STARTS}" | wc -l | tr -d ' ')" = "7" ] && pass "seven distinct day boundaries requested" || fail "boundaries: ${STARTS}"

echo
echo "=== 99.cleanup_DELETE.sh ==="
cat > "${WORK}/version_and_objects.json" <<JSON
{
  "version": "5.5-20260924",
  "files": [{"fileName": "f1.txt", "isRegularFile": true}],
  "result": [
    {"id": "comp2", "name": "btTestAccountCompositeRoute2", "account": "btTestAccount"},
    {"id": "simple2", "name": "btTestAccountSimpleRoute2", "account": "btTestAccount"},
    {"id": "tmpl1", "name": "btTestAccountPackageTemplate"},
    {"id": "sub1", "account": "btTestAccount", "application": "btTestAccountApplication"},
    {"id": "sub-else", "account": "someoneElse", "application": "btTestAccountApplication"},
    {"id": "app1", "name": "btTestAccountApplication"},
    {"id": "site1", "name": "btTestAccountPullSite1", "account": "btTestAccount"},
    {"id": "push1", "name": "btTestAccountPushSitePartner1", "account": "btTestAccount"},
    {"id": "push2", "name": "btTestAccountPushSitePartner2", "account": "btTestAccount"},
    {"id": "other", "name": "unrelatedSite", "account": "btTestAccount"},
    {"id": "elsewhere", "name": "btTestAccountPullSite1", "account": "someoneElse", "userName": "partner_to_pull_from"}
  ]
}
JSON
rm -f "${RUN:?}/state.local.sh"
# 200 to every HEAD: all three accounts exist. The site "elsewhere", of another
# account, still logs in as partner_to_pull_from, so that partner must stay.
run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json" "" "" 200
D=$(calls | grep '^DELETE' | sed 's#.*/api/v2.0/##' | tr '\n' ' ')
[ "${D}" = "routes/comp2 routes/simple2 routes/tmpl1 subscriptions/sub1 applications/btTestAccountApplication sites/site1 sites/push1 sites/push2 files/subscription/s1/f1.txt files/subscription/s1 files/subscription/s2/f1.txt files/subscription/s2 files/subscription/s3/f1.txt files/subscription/s3 files/subscription/s4/f1.txt files/subscription/s4 files/subscription/s5/f1.txt files/subscription/s5 files/subscription/s6/f1.txt files/subscription/s6 files/subscription/f1.txt files/subscription myself accounts/btTestAccount files/btTestAccount/outbound-drop/f1.txt files/btTestAccount/outbound-drop files/btTestAccount/f1.txt files/btTestAccount myself files/btTestAccount/delivered-1/f1.txt files/btTestAccount/delivered-1 files/btTestAccount/delivered-2/f1.txt files/btTestAccount/delivered-2 files/btTestAccount/f1.txt files/btTestAccount myself accounts/partner_to_push_to " ] \
    && pass "deletes the test account's objects, its folders and the account, then its folder in each partner, then a partner no site uses" \
    || fail "order: ${D}"
[[ "${OUT}" == *"The account partner_to_pull_from is kept: 1 site(s) of another test account still log in as it."* ]] \
    && pass "keeps a partner that another test account's site still logs in as" || fail "partner_to_pull_from was not kept"
LOGINS=$(echo "${OUT}" | grep '^BASIC_AUTH:' | grep -v apiadmin | sed 's/^BASIC_AUTH: //;s/:.*//' | tr '\n' ' ')
[ "${LOGINS}" = "btTestAccount partner_to_pull_from partner_to_push_to " ] && pass "removes each account's folders logged in as that account" || fail "folder logins: ${LOGINS}"
echo "${D}" | grep -qE 'sub-else|other\b|elsewhere' && fail "touched another account's or an unrelated object" || pass "leaves other accounts' objects and unrelated ones alone"
[ ! -f "${RUN}/state.local.sh" ] && pass "removes the saved ids" || fail "state file left behind"

echo
echo "=== 00.run_all.sh ==="
rm -f "${RUN:?}/state.local.sh"
echo '{"version":"5.5-20260924","id":"op-1","files":[],"result":[],"resultSet":{"returnCount":0,"totalCount":0}}' > "${WORK}/all.json"
# HEAD_STATUS is what an existence check answers: 404 unless a test says otherwise (no account is
# there, so every name is free and the partners are created). DELETE_STATUS is the status of every
# DELETE when it is set.
master() {
    OUT=$(cd "${RUN}" && PATH="${STUB_BIN:-${WORK}/bin}:${PATH}" STUB_CURL_GET_BODY="${WORK}/all.json" STUB_CURL_POST_BODY="${WORK}/all.json" \
          STUB_CURL_LOCATION_ID="new-id" STUB_CURL_STATUS="${STATUS:-201}" STUB_CURL_STATUS_HEAD="${HEAD_STATUS-404}" \
          STUB_CURL_STATUS_DELETE="${DELETE_STATUS:-}" STUB_CURL_CSRF="csrf-abc" bash ./00.run_all.sh "$@" 2>&1)
    RC=$?
}
STATUS=201 master
[ "${RC}" -eq 0 ] && pass "runs the whole thing and exits 0" || fail "exit ${RC}: $(echo "${OUT}" | tail -5)"
[[ "${OUT}" == *"=== Step 1: billable transfers before this run ==="* ]] && [[ "${OUT}" == *"=== Step 4: analysis ==="* ]] \
    && pass "runs steps 1 to 4 in order" || fail "missing step headings"
STEP_COUNT=$(echo "${OUT}" | grep -c '^--- .* of 12:')
[ "${STEP_COUNT}" -eq 12 ] && pass "runs all 12 numbered setup scripts" || fail "step count: ${STEP_COUNT}"
[[ "${OUT}" != *"=== Cleanup"* ]] && pass "without --cleanup, nothing is removed" || fail "cleaned up without being asked"
ROWS=$(echo "${OUT}" | sed -n '/=== Step 4/,$p' | grep -E '^  (partner_to_pull_from|btTestAccount|partner_to_push_to) ' | awk '{print $1, $2, $3, $4, $5}' | tr '\n' '|')
[ "${ROWS}" = "partner_to_pull_from 0 0 0 7|btTestAccount 0 0 0 12|partner_to_push_to 0 0 0 10|" ] \
    && pass "step 4: per account, before, after, added, and what the rule predicts (7, 12, 10 for one file each)" || fail "step 4 rows: ${ROWS}"
[[ "${OUT}" == *"An account did not add what the rule predicts"* ]] && [ "$(echo "${OUT}" | grep -c '   differs$')" -eq 3 ] \
    && pass "step 4 says when an account did not add what the rule predicts" || fail "no mismatch note: $(echo "${OUT}" | sed -n '/Step 4/,$p' | tail -5)"
[[ "${OUT}" != *"2.1 only inbound"* ]] && pass "the old fixed per-scenario table is gone" || fail "the old static table is still being printed"
STATUS=201 master --cleanup
[[ "${OUT}" == *"=== Cleanup: 99.cleanup_DELETE.sh ==="* ]] && pass "--cleanup runs the cleanup at the end" || fail "--cleanup did not clean up"
STATUS=500 master
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Stopped at step 1 of 12: 01.accounts_POST.sh failed"* ]] && [[ "${OUT}" != *"2 of 12"* ]]; then
    pass "stops at the first failing step, and runs nothing after it"
else
    fail "did not stop cleanly on failure (exit ${RC})"
fi
master --bogus
[ "${RC}" -eq 2 ] && pass "an unknown option is refused" || fail "--bogus exit ${RC}"

echo
echo "=== 00.run_all.sh: the home folder of the default account ==="
# A clean lab: the probe folder is made and removed, nothing else changes
SEQ="${WORK}/files_seq.txt"
STALE_BODY="${WORK}/stale.json"
echo '{"message":"Error validating request","validationErrors":["Error occurred while creating file: null"]}' > "${STALE_BODY}"
probe_run() {
    rm -f "${SEQ}.served"
    export STUB_CURL_FILES_POST_SEQUENCE="${SEQ}"
    rm -f "${RUN:?}/state.local.sh"
    STATUS=201 master "$@"
    unset STUB_CURL_FILES_POST_SEQUENCE
}
printf '201\n' > "${SEQ}"
probe_run
[ "${RC}" -eq 0 ] && pass "clean lab: the run completes" || fail "clean lab: exit ${RC}: $(echo "${OUT}" | tail -5)"
PROBES=$(calls | grep -c 'files/bt_home_probe$')
[ "${PROBES}" -eq 2 ] && calls | grep -q '^POST .*files/bt_home_probe$' && calls | grep -q '^DELETE .*files/bt_home_probe$' \
    && pass "clean lab: one probe, a POST and a DELETE of bt_home_probe" || fail "probe calls: ${PROBES}"
[ "$(calls | grep -c '^POST .*/accounts$')" -eq 3 ] && [ "$(calls | grep -c '^DELETE .*/accounts/')" -eq 0 ] \
    && pass "clean lab: the accounts are created once, and none is deleted" || fail "account calls: $(calls | grep '/accounts')"
[[ "${OUT}" == *"Account btTestAccount: scenario"* ]] && [[ "${OUT}" != *"btTestAccount_2"* ]] && [[ "${OUT}" == *"Run ./99.cleanup_DELETE.sh btTestAccount to remove"* ]] \
    && pass "clean lab: the plain default name is kept to the end" || fail "clean lab name"

# A stale home: the first probe is refused, the second works
printf '403\t%s\n201\n' "${STALE_BODY}" > "${SEQ}"
probe_run
[ "${RC}" -eq 0 ] && pass "stale home: the run completes" || fail "stale home: exit ${RC}: $(echo "${OUT}" | tail -8)"
[[ "${OUT}" == *"The home folder of btTestAccount is left over from an earlier run and belongs to another uid"* ]] \
    && [[ "${OUT}" == *"A new name is used: btTestAccount_2."* ]] && pass "stale home: says why, and the new name" || fail "no switch message"
[ "$(calls | grep '^DELETE .*/accounts/' | sed 's#.*/accounts/##' | tr '\n' ' ')" = "btTestAccount " ] \
    && pass "stale home: deletes only the test account, never a partner" || fail "deleted: $(calls | grep '^DELETE .*/accounts/')"
PAYLOAD_NAMES=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | while read -r b; do echo "$b" | base64 -d; echo; done | jq -r 'select(.type=="user") | .name' 2>/dev/null | tr '\n' ' ')
[ "${PAYLOAD_NAMES}" = "btTestAccount partner_to_pull_from partner_to_push_to btTestAccount_2 partner_to_pull_from partner_to_push_to " ] \
    && pass "stale home: step 01 runs again for btTestAccount_2 (the stub answers 201 to the existence check, so it creates the partners; a real server says Reused)" || fail "account names: ${PAYLOAD_NAMES}"
[ "$(calls | grep -c '^POST .*files/bt_home_probe$')" -eq 2 ] && [ "$(calls | grep -c '^DELETE .*files/bt_home_probe$')" -eq 1 ] \
    && pass "stale home: two probes, and the probe folder is removed once it was made" || fail "probe calls"
[[ "${OUT}" == *"Account btTestAccount_2: scenario"* ]] && [[ "${OUT}" == *"Run ./99.cleanup_DELETE.sh btTestAccount_2 to remove"* ]] \
    && pass "stale home: the cleanup hint names the final account" || fail "cleanup hint: $(echo "${OUT}" | tail -3)"
[ "$(echo "${OUT}" | grep -c '/btTestAccount_2/outbound-drop')" -gt 0 ] && pass "stale home: the drop folder follows the final name" || fail "drop folder"
probe_run --cleanup
calls | grep -q '^HEAD .*/accounts/btTestAccount_2$' && ! calls | grep -q '^HEAD .*/accounts/btTestAccount$' \
    && pass "stale home: --cleanup cleans up the final name" || fail "cleanup target: $(calls | grep '^HEAD')"

# A name the user chose is never changed
printf '403\t%s\n' "${STALE_BODY}" > "${SEQ}"
probe_run test_account
[ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Stopped at step 4 of 12: 04.files_POST_folders.sh failed"* ]] && [[ "${OUT}" == *"Hint: a 403"* ]] \
    && pass "explicit name: no switch, step 04 fails with the hint" || fail "explicit name: exit ${RC}: $(echo "${OUT}" | tail -6)"
[ "$(calls | grep -c 'bt_home_probe')" -eq 0 ] && [ "$(calls | grep -c '^DELETE .*/accounts/')" -eq 0 ] \
    && pass "explicit name: no probe, nothing deleted" || fail "explicit name made calls"
export BT_RUN_ACCOUNT=btTestAccount
probe_run
unset BT_RUN_ACCOUNT
[ "${RC}" -eq 1 ] && [ "$(calls | grep -c 'bt_home_probe')" -eq 0 ] \
    && pass "BT_RUN_ACCOUNT, even the default name, counts as chosen" || fail "BT_RUN_ACCOUNT: exit ${RC}"

# Every name up to _9 is stale
printf '403\t%s\n' "${STALE_BODY}" > "${SEQ}"
probe_run
[ "${RC}" -eq 1 ] && [[ "${OUT}" == *"every name up to btTestAccount_9"* ]] && [[ "${OUT}" == *"Run ./99.cleanup_DELETE.sh btTestAccount_9 to remove"* ]] \
    && pass "exhaustion: stops with a clear message after _9, naming the account to clean up" || fail "exhaustion: exit ${RC}: $(echo "${OUT}" | tail -5)"
DELETED=$(calls | grep '^DELETE .*/accounts/' | sed 's#.*/accounts/##' | tr '\n' ' ')
[ "${DELETED}" = "btTestAccount btTestAccount_2 btTestAccount_3 btTestAccount_4 btTestAccount_5 btTestAccount_6 btTestAccount_7 btTestAccount_8 " ] \
    && pass "exhaustion: deleted only the names this run created, never a partner" || fail "deleted: ${DELETED}"
[[ "${OUT}" != *"2 of 12"* ]] && pass "exhaustion: nothing after step 01 ran" || fail "ran on"

echo
echo "=== Another account name, and more files for scenarios 2.1 and 2.2 ==="
# Every step reads the account and the counts from settings.sh, which applies
# BT_RUN_ACCOUNT / BT_RUN_INBOUND_ONLY / BT_RUN_IN_AND_OUT over its defaults
rm -f "${RUN:?}/state.local.sh"
export BT_RUN_ACCOUNT="test_account"
run 01.accounts_POST.sh "${SERVER_NEW}"
B=$(payloads | jq -s -c '.[0]')
[ "$(echo "${B}" | jq -r .name)" = "test_account" ] && [ "$(echo "${B}" | jq -r .homeFolder)" = "/home/test_account" ] \
    && pass "BT_RUN_ACCOUNT names the account, and its home folder follows" || fail "account body: ${B}"
run 02.sites_POST_pull.sh "${SERVER_NEW}"
NAMES=$(payloads | jq -r .name | tr '\n' ' ')
[ "${NAMES}" = "test_accountPullSite1 test_accountPullSite2 test_accountPullSite3 test_accountPullSite4 test_accountPullSite5 test_accountPullSite6 " ] \
    && pass "the pull site names are derived from the account name" || fail "site names: ${NAMES}"
[ "$(payloads | jq -r .downloadFolder | sort -u)" = "/test_account/outbound-drop" ] \
    && pass "so is its folder in partner_to_pull_from, so two test accounts' files never mix" || fail "drop folder: $(payloads | jq -r .downloadFolder | sort -u)"
run 05.applications_POST.sh "${SERVER_NEW}"
[ "$(payloads | jq -s -r '.[0].name')" = "test_accountApplication" ] && pass "so is the application name, so two accounts never collide" || fail "application: $(payloads)"
unset BT_RUN_ACCOUNT

export BT_RUN_INBOUND_ONLY=3 BT_RUN_IN_AND_OUT=2
run 10.files_upload_POST.sh "${SERVER_NEW}" "${WORK}/operation.json"
PATHS=$(post_payloads | jq -r 'select(.operation=="Upload") | .filePath' | tr '\n' ' ')
[ "${PATHS}" = "/btTestAccount/outbound-drop/only_inbound_1.txt /btTestAccount/outbound-drop/only_inbound_2.txt /btTestAccount/outbound-drop/only_inbound_3.txt /btTestAccount/outbound-drop/inbound_and_one_outbound_1.txt /btTestAccount/outbound-drop/inbound_and_one_outbound_2.txt /btTestAccount/outbound-drop/inbound_and_two_outbounds.txt /btTestAccount/outbound-drop/file_1_for_compress.txt /btTestAccount/outbound-drop/file_2_for_compress.txt /btTestAccount/outbound-drop/archive_with_2_files.zip /btTestAccount/outbound-drop/archive_with_2_files_for_2_partners.zip " ] \
    && pass "3 inbound only and 2 in and out: numbered files, every other scenario unchanged" || fail "uploads: ${PATHS}"
unset BT_RUN_INBOUND_ONLY BT_RUN_IN_AND_OUT

# The same, through 00.run_all.sh's own command line
rm -f "${RUN:?}/state.local.sh"
STATUS=201 master test_account 6 12
[ "${RC}" -eq 0 ] && pass "./00.run_all.sh test_account 6 12 runs and exits 0" || fail "exit ${RC}: $(echo "${OUT}" | tail -5)"
[[ "${OUT}" == *"Account test_account: scenario 2.1 with 6 file(s), scenario 2.2 with 12 file(s)."* ]] \
    && pass "it says which account and how many files it runs" || fail "no run summary line"
PREDICTED=$(echo "${OUT}" | sed -n '/=== Step 4/,$p' | grep -E '^  (partner_to_pull_from|test_account|partner_to_push_to) ' | awk '{print $5}' | tr '\n' ' ')
[ "${PREDICTED}" = "23 28 21 " ] && pass "the rule's predictions follow the counts: 6+12+5 pulled, plus 5 repeat pushes in a chain, 12+9 arrivals" || fail "predictions: ${PREDICTED}"
[ "$(post_payloads | jq -r 'select(.type=="user") | .name' | head -n 1)" = "test_account" ] \
    && pass "the account it creates is test_account" || fail "account created: $(post_payloads | jq -r 'select(.type=="user") | .name')"
[ "$(post_payloads | jq -r 'select(.operation=="Upload") | .filePath' | grep -c 'only_inbound_')" -eq 6 ] \
    && [ "$(post_payloads | jq -r 'select(.operation=="Upload") | .filePath' | grep -c 'inbound_and_one_outbound_')" -eq 12 ] \
    && pass "it uploads 6 inbound only files and 12 in and out files" || fail "upload counts"
[[ "${OUT}" == *"Run ./99.cleanup_DELETE.sh test_account to remove"* ]] && pass "the cleanup hint names the account" || fail "cleanup hint"
STATUS=201 master test_account 6 12 --cleanup
calls | grep -q '^HEAD .*/accounts/test_account$' && pass "--cleanup after the arguments cleans up that same account" || fail "cleanup did not target test_account"
for bad in "test_account x" "test_account 0" "test_account 6 -1" "bad/name" "a 1 2 3"; do
    # shellcheck disable=SC2086
    master ${bad}
    [ "${RC}" -eq 2 ] && pass "refused: ./00.run_all.sh ${bad}" || fail "accepted: ./00.run_all.sh ${bad} (exit ${RC})"
done

# 99 and the report take the account on their own command line too
EXTRA_ARG="test_account" run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json"
calls | grep -q '^HEAD .*/accounts/test_account$' && pass "./99.cleanup_DELETE.sh test_account cleans up that account" || fail "99 with an account"
OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/report.json" bash ./billable_GET_report.sh after test_account 2>&1)
[ "$(echo "${OUT}" | grep -c '&account=test_account&')" -eq 7 ] && pass "./billable_GET_report.sh after test_account reports on that account" || fail "report account"

echo
echo "=== files_GET_download.sh ==="
# download ARGS...: runs it with the stub answering 200 to the downloads, or
# DL_STATUS to them only (the login still succeeds)
download() {
    OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${SERVER_NEW}" STUB_CURL_CSRF="csrf-abc" \
          STUB_CURL_STATUS=200 STUB_CURL_STATUS_GET="${DL_STATUS:-200}" STUB_CURL_PRINT_CODE=1 \
          bash ./files_GET_download.sh "$@" 2>&1)
    RC=$?
}
download outbound-drop/only_inbound.txt 5
[ "${RC}" -eq 0 ] && pass "downloads and exits 0" || fail "exit ${RC}: $(echo "${OUT}" | tail -3)"
DL=$(calls | grep -v version)
[ "$(echo "${DL}" | grep -c '^GET .*:8443/api/v2.0/files/outbound-drop/only_inbound.txt$')" -eq 5 ] \
    && pass "GETs the file 5 times, relative to the home folder, on the End User port" || fail "downloads: ${DL}"
echo "${DL}" | head -n 1 | grep -q '^POST .*/myself$' && echo "${DL}" | tail -n 1 | grep -q '^DELETE .*/myself$' \
    && pass "logs in once first, and out once last" || fail "login/logout: ${DL}"
[ "$(echo "${DL}" | grep -c 'myself$')" -eq 2 ] && pass "one session for all the downloads, not one login per download" || fail "logins: $(echo "${DL}" | grep -c myself)"
[[ "${OUT}" == *"5 of 5 download(s) succeeded."* ]] && pass "reports how many succeeded" || fail "summary: $(echo "${OUT}" | tail -2)"
echo "${OUT}" | grep -qF "BASIC_AUTH: btTestAccount:p@ss w0rd" && pass "logs in as the default test account" || fail "default account login"

download outbound-drop/only_inbound.txt
[ "$(calls | grep -c '^GET .*/files/')" -eq 1 ] && pass "COUNT defaults to 1" || fail "default count: $(calls | grep -c '/files/')"

download outbound-drop/only_inbound.txt 2 test_account
echo "${OUT}" | grep -qF "BASIC_AUTH: test_account:p@ss w0rd" && pass "the third argument logs in as another account" || fail "account login: $(echo "${OUT}" | grep BASIC_AUTH)"

download "/delivered-1/my file#1.txt" 1
calls | grep -q '^GET .*/api/v2.0/files/delivered-1/my%20file%231.txt$' \
    && pass "a leading / is dropped, and each part of the path is URL-encoded" || fail "path: $(calls | grep files/)"

DL_STATUS=404 download outbound-drop/missing.txt 3
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"0 of 3 download(s) succeeded."* ]] && [[ "${OUT}" == *"Failed"* ]]; then
    pass "a file that is not there: says so, and exits 1"
else
    fail "404 case (exit ${RC}): $(echo "${OUT}" | tail -3)"
fi

for bad in "" "outbound-drop/a.txt 0" "outbound-drop/a.txt x" "outbound-drop/a.txt 2 bad/name" "a 1 b c"; do
    # shellcheck disable=SC2086
    download ${bad}
    if [ "${RC}" -eq 2 ] && ! calls | grep -q '/files/'; then pass "refused, nothing sent: files_GET_download.sh ${bad}"; else fail "accepted: files_GET_download.sh ${bad} (exit ${RC})"; fi
done

OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${SERVER_OLD}" STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 bash ./files_GET_download.sh outbound-drop/a.txt 3 2>&1)
if [[ "${OUT}" == *SKIPPED* ]] && ! calls | grep -q '/files/'; then pass "skipped, and nothing downloaded, on an older server"; else fail "acted on an older server"; fi

mv "${RUN}/settings.local.sh" "${RUN}/settings.local.sh.off"
download outbound-drop/a.txt 3
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *BT_ACCOUNT_PASSWORD* ]] && ! calls | grep -q '/files/'; then pass "stops before any call when no password is set"; else fail "ran without a password (exit ${RC})"; fi
mv "${RUN}/settings.local.sh.off" "${RUN}/settings.local.sh"

# Not part of the full run, on purpose
rm -f "${RUN:?}/state.local.sh"
STATUS=201 master
[[ "${OUT}" != *"files_GET_download"* ]] && pass "00.run_all.sh does not run it" || fail "00.run_all.sh ran files_GET_download.sh"

echo
echo "=== A refused call stops the example at the first one ==="
# The calls loop over ar_admin_post, so a failure in the middle used to leave only the LAST call's
# status as the exit code: run on its own, a refused first call was hidden by the ones after it.
# stops_at SCRIPT URL_PATTERN POST_STATUS_SEQUENCE EXPECTED_POSTS: with the Nth POST answering the Nth
# status, the example must exit 1 after exactly EXPECTED_POSTS POSTs
stops_at() {
    local script="$1" pattern="$2" seq="$3" want="$4" posts
    run_by_method "${script}" "${SERVER_NEW}" STUB_STATUS_POST_SEQ="${seq}"
    posts=$(calls | grep -c "^POST .*${pattern}")
    if [ "${RC}" -eq 1 ] && [ "${posts}" -eq "${want}" ]; then
        pass "${script}: POST statuses '${seq}': exit 1 after ${want} POST(s)"
    else
        fail "${script}: POST statuses '${seq}': exit ${RC} after ${posts} POST(s), wanted exit 1 after ${want}"
    fi
}
rm -f "${RUN:?}/state.local.sh"
HEAD_STATUS=404 stops_at 01.accounts_POST.sh '/accounts$' "403 201 201" 1
HEAD_STATUS=404 stops_at 01.accounts_POST.sh '/accounts$' "201 403 201" 2
HEAD_STATUS=404 stops_at 01.accounts_POST.sh '/accounts$' "201 201 403" 3
stops_at 02.sites_POST_pull.sh '/sites$' "403 201 201 201 201 201" 1
stops_at 02.sites_POST_pull.sh '/sites$' "201 201 403 201 201 201" 3
stops_at 03.sites_POST_push.sh '/sites$' "403 201" 1
stops_at 03.sites_POST_push.sh '/sites$' "201 403" 2
stops_at 07.routes_POST_simple.sh '/routes$' "403 201 201 201 201" 1
stops_at 07.routes_POST_simple.sh '/routes$' "201 201 403 201 201" 3
stops_at 08.subscriptions_POST.sh '/subscriptions$' "403 201 201 201 201 201" 1
stops_at 08.subscriptions_POST.sh '/subscriptions$' "201 201 201 403 201 201" 4
stops_at 11.transfers_pull_POST.sh 'transfers/operations?operation=pull$' "403 202 202 202 202 202" 1
stops_at 11.transfers_pull_POST.sh 'transfers/operations?operation=pull$' "202 202 202 202 202 403" 6
# 09 needs the ids the earlier steps saved
rm -f "${RUN:?}/state.local.sh"
{ echo "export BT_ID_TEMPLATE=tmpl-1"; for n in 2 3 4 5 6; do echo "export BT_ID_SUBSCRIPTION_${n}=sub-${n}"; echo "export BT_ID_SIMPLE_${n}=simple-${n}"; done; } > "${RUN}/state.local.sh"
stops_at 09.routes_POST_composite.sh '/routes$' "403 201 201 201 201" 1
stops_at 09.routes_POST_composite.sh '/routes$' "201 201 403 201 201" 3
run_by_method 07.routes_POST_simple.sh "${SERVER_NEW}" STUB_STATUS_POST_SEQ="403 201 201 201 201"
[[ "${OUT}" == *"HTTP 403"* ]] && pass "07: the refused call is printed" || fail "07: no HTTP 403 in the output"
rm -f "${RUN:?}/state.local.sh"

echo
echo "=== 04, 10 and 12: a refused call stops the example ==="
# 04: the folders are POSTed as the test account (7), then as each partner. The 8th is refused (409)
SEQ="${WORK}/files_seq_stop.txt"
printf '201\n201\n201\n201\n201\n201\n201\n409\n' > "${SEQ}"
run_by_method 04.files_POST_folders.sh "${SERVER_NEW}" STUB_CURL_FILES_POST_SEQUENCE="${SEQ}"
rm -f "${SEQ}.served"
if [ "${RC}" -eq 1 ] && [ "$(calls | grep -c '^POST .*/files/')" -eq 8 ] && [[ "${OUT}" == *"HTTP 409"* ]] && calls | tail -n 1 | grep -q '^DELETE .*myself$'; then
    pass "04: the 8th folder is refused: exit 1, no folder after it is tried, and it logs out"
else
    fail "04 refused folder: exit ${RC}, $(calls | grep -c '^POST .*/files/') folder POSTs"
fi
run_by_method 04.files_POST_folders.sh "${SERVER_NEW}" STUB_CURL_STATUS_FILES=409
if [ "${RC}" -eq 1 ] && [ "$(calls | grep -c '^POST .*/files/')" -eq 1 ]; then pass "04: a refused first folder: exit 1 after one POST"; else fail "04 first folder: exit ${RC}"; fi
# 10: no operation id, then a refused content call
echo '{"error":"no such folder"}' > "${WORK}/no_id.json"
POST_BODY="${WORK}/no_id.json" run_by_method 10.files_upload_POST.sh "${SERVER_NEW}"
if [ "${RC}" -eq 1 ] && [ "$(calls | grep -c '^POST .*fileOperations$')" -eq 1 ] && ! calls | grep -q '^PUT ' && calls | tail -n 1 | grep -q '^DELETE .*myself$'; then
    pass "10: no operation id: exit 1 after the first declaration, no content sent, and it logs out"
else
    fail "10 no id: exit ${RC}, $(calls | grep -c '^POST .*fileOperations$') declarations"
fi
POST_BODY="${WORK}/operation.json" run_by_method 10.files_upload_POST.sh "${SERVER_NEW}" STUB_STATUS_PUT=403
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"HTTP 403"* ]] && [ "$(calls | grep -c '^PUT ')" -eq 1 ] && calls | tail -n 1 | grep -q '^DELETE .*myself$'; then
    pass "10: a refused content call: exit 1, the next files are not uploaded, and it logs out"
else
    fail "10 refused PUT: exit ${RC}, $(calls | grep -c '^PUT ') puts"
fi
# 12: a listing the server refuses
run_by_method 12.files_GET_result.sh "${SERVER_NEW}"
[ "${RC}" -eq 0 ] && pass "12: exits 0 when every listing works" || fail "12: exit ${RC}"
run_by_method 12.files_GET_result.sh "${SERVER_NEW}" STUB_STATUS_GET=403
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"The listing was refused (HTTP 403)."* ]]; then pass "12: a refused listing is said so, and it exits 1"; else fail "12 refused listing: exit ${RC}"; fi

echo
echo "=== 99.cleanup_DELETE.sh: what could not be deleted ==="
# Same fixture as above: the test account's objects, and a site of another account that logs in as
# partner_to_pull_from, so that partner must stay
printf 'export BT_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
HEAD_STATUS=200 run_by_method 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json" STUB_STATUS_DELETE=403
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Not everything was removed. Left on the server:"* ]] \
   && [[ "${OUT}" == *"  routes comp2 (HTTP 403)"* ]] && [[ "${OUT}" == *"  sites push2 (HTTP 403)"* ]] \
   && [[ "${OUT}" == *"  the folder /subscription/s1 of btTestAccount (HTTP 403)"* ]] \
   && [[ "${OUT}" == *"  the account btTestAccount (HTTP 403)"* ]] && [[ "${OUT}" == *"  the account partner_to_push_to (HTTP 403)"* ]]; then
    pass "refused deletes: exit 1, and the objects, folders and accounts that are left are named"
else
    fail "refused deletes (exit ${RC}): $(echo "${OUT}" | sed -n '/Not everything/,$p')"
fi
[ -f "${RUN}/state.local.sh" ] && [[ "${OUT}" == *"The saved ids in "*"state.local.sh are kept."* ]] && [[ "${OUT}" == *"99.cleanup_DELETE.sh btTestAccount again."* ]] \
    && pass "refused deletes: the saved ids are kept, and it says how to try again" || fail "state file removed with objects left"
printf 'export BT_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
HEAD_STATUS=200 run_by_method 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json" STUB_STATUS_DELETE=404
[ "${RC}" -eq 0 ] && [ ! -f "${RUN}/state.local.sh" ] && pass "a delete that answers 404 (already gone) is not a failure" || fail "404 treated as a failure (exit ${RC})"
printf 'export BT_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
HEAD_STATUS=200 run_by_method 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json" STUB_STATUS_GET=500
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"The list of routes could not be read (HTTP 500)"* ]] && [[ "${OUT}" == *"  sites: the list could not be read (HTTP 500)"* ]] \
   && ! calls | grep -q '^DELETE .*/\(routes\|sites\|subscriptions\|applications\)/' && [ -f "${RUN}/state.local.sh" ]; then
    pass "a refused list: exit 1, nothing is deleted from it, and it is named as left"
else
    fail "refused list (exit ${RC}): $(echo "${OUT}" | sed -n '/Not everything/,$p')"
fi
# The partner is deleted only once nobody is known to log in as it: an unreadable list of sites is not "nobody"
if [[ "${OUT}" == *"The list of sites could not be read, so the account partner_to_push_to is kept."* ]] && ! calls | grep -q '^DELETE .*/accounts/partner_'; then
    pass "an unreadable list of sites: the partner is kept, not deleted"
else
    fail "partner deleted without reading the sites: $(calls | grep 'DELETE .*accounts')"
fi
printf 'export BT_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
HEAD_STATUS=500 run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json"
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Could not tell whether the account btTestAccount exists (HTTP 500)."* ]] && [[ "${OUT}" != *"Nothing to delete"* ]] \
   && ! calls | grep -q '^DELETE .*/accounts/' && [ -f "${RUN}/state.local.sh" ]; then
    pass "an account that cannot be checked: exit 1, not reported as gone, nothing deleted, the saved ids kept"
else
    fail "unchecked account (exit ${RC}): $(echo "${OUT}" | tail -n 5)"
fi
printf 'export BT_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
echo '{"version":"5.5-20260924","result":[]}' > "${WORK}/version_no_objects.json"
HEAD_STATUS=200 run_by_method 99.cleanup_DELETE.sh "${WORK}/version_no_objects.json" STUB_CURL_STATUS_FILES=404
if [ "${RC}" -eq 0 ] && [[ "${OUT}" == *"The folder /subscription/s1 of btTestAccount is not there."* ]] && ! calls | grep -q '^DELETE .*/files/'; then
    pass "a folder that is not there: skipped, nothing deleted from it, exit 0"
else
    fail "missing folder (exit ${RC}): $(calls | grep files/ | head -n 3)"
fi
cat > "${WORK}/version_and_odd_names.json" <<JSON
{"version": "5.5-20260924", "files": [
  {"fileName": "my file#1.txt", "isRegularFile": true},
  {"fileName": "a#1.txt", "isRegularFile": true},
  {"fileName": "50% off?.txt", "isRegularFile": true}]}
JSON
HEAD_STATUS=200 run 99.cleanup_DELETE.sh "${WORK}/version_and_odd_names.json" "" "" 200
ODD=$(calls | grep '^DELETE .*/files/subscription/s1/' | sed 's#.*/files/subscription/s1/##' | tr '\n' ' ')
[ "${ODD}" = "my%20file%231.txt a%231.txt 50%25%20off%3F.txt " ] \
    && pass "a space, a #, a % and a ? in a file name are encoded in the DELETE" || fail "encoded names: ${ODD}"
# The run's exit code is the cleanup's
HEAD_STATUS=200 DELETE_STATUS=403 STATUS=201 master --cleanup
[ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Not everything was removed."* ]] && pass "00.run_all.sh --cleanup exits 1 when the cleanup left something" || fail "--cleanup with refused deletes: exit ${RC}"
rm -f "${RUN:?}/state.local.sh"
STATUS=201 master --cleanup
[ "${RC}" -eq 0 ] && pass "00.run_all.sh --cleanup exits 0 when it removed everything" || fail "--cleanup: exit ${RC}"

echo
echo "=== 00.run_all.sh: the stale account cannot be deleted ==="
printf '403\t%s\n201\n' "${STALE_BODY}" > "${SEQ}"
DELETE_STATUS=403 probe_run
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"The account btTestAccount could not be deleted, so the run stops here."* ]] && [[ "${OUT}" != *"2 of 12"* ]]; then
    pass "an account that cannot be deleted stops the run, before anything else is made"
else
    fail "refused delete of the stale account (exit ${RC}): $(echo "${OUT}" | tail -n 4)"
fi
# A name that is already an account is skipped. The existence checks, in order: the two partners in
# step 01 (404: created), then btTestAccount_2 (200: taken), then btTestAccount_3 (404: free)
printf '403\t%s\n201\n' "${STALE_BODY}" > "${SEQ}"
rm -f "${WORK}/counter."*
STUB_BIN="${WORK}/bin_by_method" STUB_COUNTER="${WORK}/counter" STUB_STATUS_HEAD_SEQ="404 404 200 404" HEAD_STATUS= probe_run
[ "${RC}" -eq 0 ] && [[ "${OUT}" == *"A new name is used: btTestAccount_3."* ]] \
    && pass "a name that is already an account is skipped: btTestAccount_3 is used" || fail "taken name (exit ${RC}): $(echo "${OUT}" | grep -i 'new name')"

echo
echo "=== Guard rails ==="
rm -f "${RUN:?}/state.local.sh"
for s in 00.run_all.sh 01.accounts_POST.sh 02.sites_POST_pull.sh 03.sites_POST_push.sh 04.files_POST_folders.sh \
         10.files_upload_POST.sh 11.transfers_pull_POST.sh 12.files_GET_result.sh billable_GET_report.sh 99.cleanup_DELETE.sh; do
    run "${s}" "${SERVER_OLD}"
    if [ "${RC}" -eq 0 ] && [[ "${OUT}" == *SKIPPED* ]] && ! echo "${OUT}" | grep -qE '^METHOD: (POST|DELETE|PUT)'; then
        pass "${s}: skipped, and sends nothing, on an older server"
    else
        fail "${s}: acted on an older server (exit ${RC})"
    fi
done

mv "${RUN}/settings.local.sh" "${RUN}/settings.local.sh.off"
for s in 01.accounts_POST.sh 02.sites_POST_pull.sh 03.sites_POST_push.sh 04.files_POST_folders.sh 10.files_upload_POST.sh; do
    run "${s}" "${SERVER_NEW}"
    if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *BT_ACCOUNT_PASSWORD* ]] && ! echo "${OUT}" | grep -qE '^METHOD: (POST|PUT)'; then
        pass "${s}: stops and sends nothing when no password is set"
    else
        fail "${s}: ran without a password (exit ${RC})"
    fi
done
mv "${RUN}/settings.local.sh.off" "${RUN}/settings.local.sh"

echo
echo "=== Pairs ==="
for f in $(cd "${REPO}" && git ls-files "${FEATURE}/*.sh" 2>/dev/null); do
    [ -f "${REPO}/${f%.sh}.bat" ] || fail "no bat twin: $(basename "$f")"
done
pass "every tracked script has a bat twin"

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_feature_billable_transfers: PASS"; else echo "test_feature_billable_transfers: FAIL"; fi
exit "${FAILED}"
