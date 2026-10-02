#!/bin/bash
# ==============================================================================
# Run the Features/trigger-route-after-completed-pull examples against a stub
# curl, and check what they would send.
#
# The examples are copied into a scratch tree together with the shared version
# check, so a settings.local.sh on the developer's machine cannot change the
# result.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
FEATURE="Features/trigger-route-after-completed-pull"

WORK="${TESTS_DIR}/output/feature_trigger_route_pull"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/Features" "${WORK}/Admin/API 2.0/bash"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp -R "${REPO}/Features/lib" "${WORK}/Features/lib"
cp -R "${REPO}/${FEATURE}" "${WORK}/${FEATURE}"
rm -f "${WORK}/${FEATURE}/settings.local.sh" "${WORK}/${FEATURE}/settings.local.bat" "${WORK}/${FEATURE}/state.local.sh" "${WORK}/${FEATURE}/state.local.bat"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/Admin/API 2.0/bash/set_variables.sh"
# An Admin port different from the End User one, as on a root install
sed 's/^export ST_PORT=.*/export ST_PORT="444"/' "${WORK}/Admin/API 2.0/bash/set_variables.sh" > "${WORK}/set_variables.tmp" \
    && mv "${WORK}/set_variables.tmp" "${WORK}/Admin/API 2.0/bash/set_variables.sh"
RUN="${WORK}/${FEATURE}"

# A password with characters that break hand-built JSON
TRICKY='p"a\ss $x'
printf 'export AR_ACCOUNT_PASSWORD=%q\n' "${TRICKY}" > "${RUN}/settings.local.sh"
echo 'export AR_WAIT_SECONDS=0' >> "${RUN}/settings.local.sh"
echo 'export AR_STEP_PAUSE_SECONDS=0' >> "${RUN}/settings.local.sh"

SERVER_NEW="${WORK}/version_new.json"; echo '{"version":"5.5-20260924"}' > "${SERVER_NEW}"
SERVER_OLD="${WORK}/version_old.json"; echo '{"version":"5.5-20260923"}' > "${SERVER_OLD}"

# run SCRIPT VERSION_FILE -> sets OUT (stdout+stderr), RC
run() {
    OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="$2" \
          STUB_CURL_LOCATION_ID="${3:-new-id}" STUB_CURL_STATUS="${4:-201}" STUB_CURL_CSRF="csrf-abc" bash "./$1" 2>&1)
    RC=$?
}
# the method and URL of every request the example made, in order
calls() { echo "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL:/ {print m, $2}'; }
payload() { echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | head -n 1 | base64 -d; }
# the method and URL of the last request, which is the one the example makes
last_call() { echo "${OUT}" | grep -E '^(METHOD|URL):' | tail -n 2 | tr '\n' ' '; }

echo "=== 01.accounts_POST.sh ==="
run 01.accounts_POST.sh "${SERVER_NEW}"
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
[[ "$(last_call)" == *"METHOD: POST URL: https://"*"/api/v2.0/accounts"* ]] && pass "POSTs to /accounts" || fail "wrong call: $(last_call)"
B=$(payload)
echo "${B}" | jq -e . >/dev/null 2>&1 && pass "the body is valid JSON" || fail "body is not JSON: ${B}"
[ "$(echo "${B}" | jq -r .name)" = "arTestAccount" ] && pass "account name" || fail "account name"
[ "$(echo "${B}" | jq -r .type)" = "user" ] && pass "account type is user" || fail "account type"
[ "$(echo "${B}" | jq -r .homeFolder)" = "/home/arTestAccount" ] && pass "home folder" || fail "home folder"
[ "$(echo "${B}" | jq -c .transfersWebServiceAllowed)" = "true" ] && pass "the web service right is on, so the account can use the End User API" || fail "transfersWebServiceAllowed: $(echo "${B}" | jq -c .transfersWebServiceAllowed)"
[ "$(echo "${B}" | jq -r .user.passwordCredentials.password)" = "${TRICKY}" ] && pass "a password with quotes and backslashes survives" || fail "password mangled"

echo
echo "=== 02.sites_POST_pull.sh ==="
run 02.sites_POST_pull.sh "${SERVER_NEW}"
[[ "$(last_call)" == *"METHOD: POST URL: https://"*"/api/v2.0/sites"* ]] && pass "POSTs to /sites" || fail "wrong call: $(last_call)"
B=$(payload)
echo "${B}" | jq -e . >/dev/null 2>&1 && pass "the body is valid JSON" || fail "body is not JSON: ${B}"
[ "$(echo "${B}" | jq -r .name)" = "arTestPullSite" ] && pass "site name" || fail "site name"
[ "$(echo "${B}" | jq -r .type)" = "ssh" ] && [ "$(echo "${B}" | jq -r .protocol)" = "ssh" ] && pass "SSH site, with its protocol set" || fail "site type/protocol"
[ "$(echo "${B}" | jq -r .port)" = "8022" ] && pass "SSH port is 8022" || fail "port: $(echo "${B}" | jq -r .port)"
HOST=$(grep -o 'ST_SERVER="[^"]*"' "${WORK}/Admin/API 2.0/bash/set_variables.sh" | cut -d'"' -f2)
[ "$(echo "${B}" | jq -r .host)" = "${HOST}" ] && pass "host defaults to the server itself" || fail "host"
[ "$(echo "${B}" | jq -r .downloadFolder)" = "/outbound-drop" ] && pass "downloads from outbound-drop" || fail "download folder"
[ "$(echo "${B}" | jq -r .postTransmissionActions.doAsIn)" = '${stenv.target}_PULLED' ] && pass "renames files on receive to <name>_PULLED" || fail "doAsIn: $(echo "${B}" | jq -r .postTransmissionActions.doAsIn)"
[ "$(echo "${B}" | jq -r .account)" = "arTestAccount" ] && pass "belongs to the test account" || fail "site account"
[ "$(echo "${B}" | jq -c .usePassword)" = "true" ] && pass "usePassword is a JSON boolean, not a string" || fail "usePassword: $(echo "${B}" | jq -c .usePassword)"
[ "$(echo "${B}" | jq -r .password)" = "${TRICKY}" ] && pass "password survives" || fail "password mangled"

echo
echo "=== 03.sites_POST_push.sh ==="
run 03.sites_POST_push.sh "${SERVER_NEW}"
B=$(payload)
echo "${B}" | jq -e . >/dev/null 2>&1 && pass "the body is valid JSON" || fail "body is not JSON: ${B}"
[ "$(echo "${B}" | jq -r .name)" = "arTestPushSite" ] && pass "site name" || fail "site name"
[ "$(echo "${B}" | jq -r .protocol)" = "ssh" ] && pass "push site: protocol is set" || fail "push site: no protocol"
[ "$(echo "${B}" | jq -r .postTransmissionActions.doAsOut)" = '${stenv.target}_PUSHED' ] && pass "renames files on send to <name>_PUSHED" || fail "doAsOut: $(echo "${B}" | jq -r .postTransmissionActions.doAsOut)"
[ "$(echo "${B}" | jq -r .uploadFolder)" = "/delivered" ] && pass "uploads to delivered" || fail "upload folder"
[ "$(echo "${B}" | jq -r .uploadFolder)" != "$(. "${RUN}/settings.sh" && echo "${AR_SUBSCRIPTION_FOLDER}")" ] \
    && pass "the upload folder is not the subscription folder" || fail "upload folder equals the subscription folder: the route would trigger itself"

echo
echo "=== 04.files_POST_folders.sh ==="
run 04.files_POST_folders.sh "${SERVER_NEW}"
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
# The End User login must actually carry the real account name and password -
# not rely on a shared-lib variable that was never set for this feature's own
# prefix, which would silently log in as ":" and fail every call after it.
# grep -F, not the first BASIC_AUTH line: the version check's own admin-
# authenticated GET /version always comes first and is a different login.
echo "${OUT}" | grep -qF "BASIC_AUTH: arTestAccount:${TRICKY}" \
    && pass "logs in to the End User API with the real account name and password" \
    || fail "End User login credentials: $(echo "${OUT}" | grep '^BASIC_AUTH:' | sed -n 2p)"
EU=$(calls | grep -v 'version')
echo "${EU}" | head -n 1 | grep -q '^POST .*:8443/api/v2.0/myself$' && pass "logs in first, on the End User port" || fail "first call: $(echo "${EU}" | head -n 1)"
[ "$(echo "${EU}" | grep -c '^POST .*:8443/api/v2.0/files/\(outbound-drop\|delivered\)$')" -eq 2 ] && pass "one POST to /files/<name> per folder, on the End User port" || fail "calls: ${EU}"
echo "${EU}" | tail -n 1 | grep -q '^DELETE .*:8443/api/v2.0/myself$' && pass "logs out last" || fail "last call: $(echo "${EU}" | tail -n 1)"
[ "$(echo "${OUT}" | grep -c '^HEADER: csrfToken: csrf-abc$')" -eq 3 ] && pass "sends the csrfToken from the login on every later call" || fail "csrf headers: $(echo "${OUT}" | grep -c 'HEADER: csrfToken')"
BODIES=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | while read -r b; do echo "$b" | base64 -d | jq -c .; done | sort -u)
[ "${BODIES}" = '{"isDirectory":true,"isRegularFile":false,"isSymbolicLink":false,"isOther":false,"isShared":false}' ] && pass "describes each as a directory, with the flags the server returns for one" || fail "bodies: ${BODIES}"
run 04.files_POST_folders.sh "${SERVER_NEW}" x 401
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Could not log in"* ]] && [[ "${OUT}" == *"HTTP 401"* ]] && [[ "${OUT}" == *"Response headers"* ]] && ! calls | grep -q '/files$'; then pass "a failed login says so, and creates nothing"; else fail "went on after a failed login (exit ${RC})"; fi

echo
echo "=== 05.files_upload_POST.sh ==="
echo '{"id":"op-42","status":"RUNNING"}' > "${WORK}/operation.json"
run04() { OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${SERVER_NEW}" STUB_CURL_POST_BODY="$1" STUB_CURL_CSRF="csrf-abc" bash ./05.files_upload_POST.sh 2>&1); RC=$?; }
run04 "${WORK}/operation.json"
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
C=$(calls | grep fileOperations)
[ "$(echo "${C}" | grep -c 'fileOperations$')" -eq 3 ] && pass "declares one upload per sample file (3)" || fail "declarations: ${C}"
[ "$(echo "${C}" | grep -c '^PUT .*fileOperations/op-42$')" -eq 3 ] && pass "sends each content to the returned operation id, with PUT" || fail "content calls: ${C}"
echo "${C}" | grep -q ':8443/' && pass "uses the End User port, 8443" || fail "port: ${C}"
calls | grep -v version | head -n 1 | grep -q '^POST .*:8443/api/v2.0/myself$' && calls | tail -n 1 | grep -q '^DELETE .*myself$' && pass "logs in first and out last" || fail "no login/logout around the uploads"
echo "${C}" | grep -q ':444/' && fail "used the Admin port" || pass "does not use the Admin port (444)"
FIRST=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | head -n 1 | base64 -d)
[ "$(echo "${FIRST}" | jq -r .operation)" = "Upload" ] && pass "declares an Upload" || fail "operation: ${FIRST}"
[ "$(echo "${FIRST}" | jq -r .filePath)" = "/outbound-drop/pull_test_1.txt" ] && pass "into the pull folder" || fail "filePath: ${FIRST}"
[ "$(echo "${FIRST}" | jq -r .customAttributes.transferMode)" = "ASCII" ] && pass "transfer mode ASCII" || fail "transfer mode"
echo '{"error":"no such folder"}' > "${WORK}/no_id.json"
run04 "${WORK}/no_id.json"
if [ "${RC}" -eq 1 ] && ! calls | grep -q 'fileOperations/'; then pass "no operation id: stops, and sends no content"; else fail "went on without an id (exit ${RC})"; fi

echo
echo "=== 06 to 10: the routes, application and subscription bodies ==="
rm -f "${RUN}/state.local.sh"
expected_condition="\${stenv['target'].matches('.*\\\\.trigger')?1:0}"

run 06.routes_POST_template.sh "${SERVER_NEW}" tmpl-1
B=$(payload)
[ "$(echo "${B}" | jq -r .type)" = "TEMPLATE" ] && [ "$(echo "${B}" | jq -r .name)" = "arTestPackageTemplate" ] && pass "06: a TEMPLATE route" || fail "06 body: ${B}"
grep -q 'AR_ID_TEMPLATE=tmpl-1' "${RUN}/state.local.sh" && pass "06: the new id is saved from the Location header" || fail "06: id not saved"

run 10.routes_POST_composite.sh "${SERVER_NEW}" comp-4
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"AR_ID_SIMPLE is not saved"* ]] && ! echo "${OUT}" | grep -q '^METHOD: POST'; then pass "10: stops, and sends nothing, when an earlier step has not been run"; else fail "10 ran without its ids (exit ${RC})"; fi

run 07.routes_POST_simple.sh "${SERVER_NEW}" simple-2
B=$(payload)
[ "$(echo "${B}" | jq -r .type)" = "SIMPLE" ] && pass "07: a SIMPLE route" || fail "07 body: ${B}"
[ "$(echo "${B}" | jq -r '.steps | length')" = "1" ] && [ "$(echo "${B}" | jq -r '.steps[0].type')" = "SendToPartner" ] && pass "07: one SendToPartner step, and no Compress" || fail "07 steps: ${B}"
[ "$(echo "${B}" | jq -r '.steps[0].transferSiteExpression')" = "arTestPushSite#!#CVD#!#" ] && pass "07: sends to the push site" || fail "07 site: ${B}"

run 08.applications_POST.sh "${SERVER_NEW}" app-5
B=$(payload)
[ "$(echo "${B}" | jq -r .type)" = "AdvancedRouting" ] && [ "$(echo "${B}" | jq -r .name)" = "arTestPullApplication" ] && pass "08: an AdvancedRouting application" || fail "08 body: ${B}"
grep -q 'AR_ID_APPLICATION=app-5' "${RUN}/state.local.sh" && pass "08: the new id is saved" || fail "08: id not saved"

run 09.subscriptions_POST.sh "${SERVER_NEW}" sub-3
B=$(payload)
echo "${B}" | jq -e . >/dev/null 2>&1 && pass "09: valid JSON" || fail "09 body: ${B}"
[ "$(echo "${B}" | jq -r .type)" = "AdvancedRouting" ] && [ "$(echo "${B}" | jq -r .account)" = "arTestAccount" ] && pass "09: an Advanced Routing subscription on the test account" || fail "09 type/account"
[ "$(echo "${B}" | jq -r .application)" = "arTestPullApplication" ] && pass "09: belongs to the application created in step 8" || fail "09 application: $(echo "${B}" | jq -r .application)"
[ "$(echo "${B}" | jq -r .folder)" = "/subscription" ] && pass "09: watches the subscription folder" || fail "09 folder"
[ "$(echo "${B}" | jq -r '.transferConfigurations[0].site')" = "arTestPullSite" ] && pass "09: pulls from the pull site" || fail "09 site"
[ "$(echo "${B}" | jq -r .createFilesList.createFilesListEnabled)" = "true" ] && pass "09: creates a file listing the pulled files" || fail "09 createFilesList"
NAME=$(echo "${B}" | jq -r .createFilesList.createFilesListFilename)
[ "${NAME}" = "file_\${date('yyyyddMMHHmmss')}.trigger" ] && pass "09: the trigger file name carries the date expression" || fail "09 trigger name: ${NAME}"
[ "$(echo "${B}" | jq -r .postTransmissionActions.submitFilterType)" = "TRIGGER_FILE_CONTENT" ] && pass "09: submits the files read from the trigger file" || fail "09 submitFilterType"
[ "$(echo "${B}" | jq -r .postTransmissionActions.triggerFileOption)" = "fail" ] && pass "09: fails if a listed file is missing" || fail "09 triggerFileOption"
[ "$(echo "${B}" | jq -c .postTransmissionActions.triggerOnConditionEnabled)" = "true" ] && pass "09: the condition is switched on, which the server requires" || fail "09 triggerOnConditionEnabled"
COND=$(echo "${B}" | jq -r .postTransmissionActions.triggerOnConditionExpression)
[ "${COND}" = "${expected_condition}" ] && pass "09: the trigger condition keeps its two backslashes" || fail "09 condition: ${COND} (wanted ${expected_condition})"
# The condition must match the file the name produces: same extension
[[ "${NAME}" == *.trigger ]] && [[ "${COND}" == *"trigger"* ]] && pass "09: name and condition agree on .trigger" || fail "09: name and condition disagree"

run 10.routes_POST_composite.sh "${SERVER_NEW}" comp-4
B=$(payload)
[ "$(echo "${B}" | jq -r .type)" = "COMPOSITE" ] && [ "$(echo "${B}" | jq -r .routeTemplate)" = "tmpl-1" ] && pass "10: a COMPOSITE route built from the template" || fail "10 body: ${B}"
[ "$(echo "${B}" | jq -r '.subscriptions[0]')" = "sub-3" ] && pass "10: attached to the subscription" || fail "10 subscription"
[ "$(echo "${B}" | jq -r '.steps[0].executeRoute')" = "simple-2" ] && pass "10: runs the simple route" || fail "10 executeRoute"
for k in AR_ID_TEMPLATE AR_ID_SIMPLE AR_ID_APPLICATION AR_ID_SUBSCRIPTION AR_ID_COMPOSITE; do grep -q "${k}=" "${RUN}/state.local.sh" || fail "state is missing ${k}"; done
pass "all five ids are saved for the cleanup"

run 09.subscriptions_POST.sh "${SERVER_NEW}" sub-x 422
if [ "$(grep -c 'AR_ID_SUBSCRIPTION=' "${RUN}/state.local.sh")" -eq 1 ] && [[ "${OUT}" == *"HTTP 422"* ]]; then pass "a failed create prints the code and saves no id"; else fail "a 422 was treated as success"; fi

echo
echo "=== 11.transfers_pull_POST.sh ==="
run 11.transfers_pull_POST.sh "${SERVER_NEW}" op-9 202
C=$(calls | tail -n 1)
[[ "${C}" == "POST https://"*"/api/v2.0/transfers/operations?operation=pull" ]] && pass "POSTs the pull operation" || fail "call: ${C}"
B=$(payload)
[ "$(echo "${B}" | jq -r .accountName)" = "arTestAccount" ] && [ "$(echo "${B}" | jq -r .site)" = "arTestPullSite" ] && pass "pulls from the pull site for the test account" || fail "pull body: ${B}"
[ "$(echo "${B}" | jq -r .destinationDirectory)" = "/subscription" ] && pass "pulls into the subscription folder" || fail "destination"

echo
echo "=== 12.files_PUT_triggerfile.sh ==="
cat > "${WORK}/version_and_triggers.json" <<JSON
{"version": "5.5-20260924", "files": [
  {"fileName": "file_old.trigger", "isRegularFile": true, "lastModifiedTime": 100},
  {"fileName": "file_new.trigger", "isRegularFile": true, "lastModifiedTime": 200},
  {"fileName": "pull_test_1.txt_PULLED", "isRegularFile": true, "lastModifiedTime": 150}]}
JSON
run12() { OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="$1" STUB_CURL_POST_BODY="${WORK}/operation.json" STUB_CURL_CSRF="csrf-abc" bash ./12.files_PUT_triggerfile.sh 2>&1); RC=$?; }
run12 "${WORK}/version_and_triggers.json"
[ "${RC}" -eq 0 ] && pass "runs on a new enough server" || fail "exit ${RC}"
declare_body=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | head -n 1 | base64 -d)
[ "$(echo "${declare_body}" | jq -r .filePath)" = "/subscription/file_new.trigger" ] && pass "replaces the NEWEST trigger file, under the same name" || fail "filePath: ${declare_body}"
FLOW=$(calls | grep -E 'files/subscription/file_new.trigger$|fileOperations' | sed 's#https://[^/]*/api/v2.0/##' | tr '\n' ',')
[ "${FLOW}" = "DELETE files/subscription/file_new.trigger,POST fileOperations,PUT fileOperations/op-42," ] && pass "deletes the old trigger file first (the server will not write over it), then uploads" || fail "flow: ${FLOW}"
calls | grep -q '^PUT .*fileOperations/op-42$' && pass "sends the content with PUT to the returned operation id" || fail "calls: $(calls | grep fileOperations)"
echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | tail -n 1 | base64 -d > "${WORK}/trigger_content.txt"
EXPECT=$(printf 'pull_test_1.txt_PULLED\npull_test_2.txt_PULLED\npull_test_3.txt_PULLED')
[ "$(cat "${WORK}/trigger_content.txt")" = "${EXPECT}" ] && [ "$(wc -l < "${WORK}/trigger_content.txt" | tr -d ' ')" = "3" ] && pass "the content is the three renamed file names, one per line" || fail "content: $(cat "${WORK}/trigger_content.txt")"
# If the old file cannot be deleted, the new one gets another name that still ends .trigger
OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/version_and_triggers.json" STUB_CURL_POST_BODY="${WORK}/operation.json" \
      STUB_CURL_CSRF="csrf-abc" STUB_CURL_STATUS_DELETE=403 bash ./12.files_PUT_triggerfile.sh 2>&1)
FB=$(echo "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | head -n 1 | base64 -d | jq -r .filePath)
[ "${FB}" = "/subscription/file_new_fixed.trigger" ] && pass "if the delete is refused, uploads as <name>_fixed.trigger" || fail "fallback name: ${FB}"
printf '{"version": "5.5-20260924", "files": []}' > "${WORK}/version_no_trigger.json"
run12 "${WORK}/version_no_trigger.json"
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"No trigger file"* ]] && ! calls | grep -q 'fileOperations'; then pass "no trigger file: says so, and uploads nothing"; else fail "no-trigger case (exit ${RC})"; fi

echo
echo "=== 13.files_GET_result.sh ==="
cat > "${WORK}/version_and_files.json" <<JSON
{"version": "5.5-20260924", "files": [
  {"fileName": "file_01102026.trigger", "isRegularFile": true, "size": 120},
  {"fileName": "pull_test_1.txt", "isRegularFile": true, "size": 35},
  {"fileName": "sub", "isRegularFile": false, "isDirectory": true}]}
JSON
run 13.files_GET_result.sh "${WORK}/version_and_files.json"
[ "${RC}" -eq 0 ] && pass "exits 0 when the last folder has files" || fail "exit ${RC}"
[[ "${OUT}" == *"delivered: 2 file(s)"* ]] && [[ "${OUT}" == *"pull_test_1.txt  (35 bytes)"* ]] && pass "lists the regular files of each folder, not directories" || fail "listing: ${OUT}"
[ "$(calls | grep -c '^GET .*/files/\(outbound-drop\|subscription\|delivered\)$')" -ge 3 ] && pass "asks for all three folders" || fail "folders asked: $(calls | grep files/)"
printf '{"version": "5.5-20260924", "files": []}' > "${WORK}/version_and_nofiles.json"
run 13.files_GET_result.sh "${WORK}/version_and_nofiles.json"
[ "${RC}" -eq 1 ] && [[ "${OUT}" == *"delivered: 0 file(s)"* ]] && pass "exits 1 when nothing reached the last folder" || fail "empty case: exit ${RC}"

echo
echo "=== 99.cleanup_DELETE.sh ==="
cat > "${WORK}/version_and_objects.json" <<JSON
{
  "version": "5.5-20260924",
  "result": [
    {"id": "comp-4",    "name": "arTestPullPackage",     "account": "arTestAccount"},
    {"id": "simple-2",  "name": "arTestSendToPushSite",  "account": "arTestAccount"},
    {"id": "tmpl-1",    "name": "arTestPackageTemplate"},
    {"id": "sub-3",     "account": "arTestAccount", "application": "arTestPullApplication"},
    {"id": "sub-else",  "account": "someoneElse",   "application": "arTestPullApplication"},
    {"id": "app-5",     "name": "arTestPullApplication"},
    {"id": "site-pull", "name": "arTestPullSite", "account": "arTestAccount"},
    {"id": "site-push", "name": "arTestPushSite", "account": "arTestAccount"},
    {"id": "site-other","name": "arTestPullSite", "account": "someoneElse"},
    {"id": "site-else", "name": "unrelated",      "account": "arTestAccount"},
    {"id": "route-else","name": "someOtherRoute"}
  ]
}
JSON
# Even with no saved ids: it finds everything by name
rm -f "${RUN}/state.local.sh"
run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json"
D=$(calls | grep '^DELETE')
ORDER=$(echo "${D}" | sed 's#.*/api/v2.0/##' | tr '\n' ' ')
[ "${ORDER}" = "routes/comp-4 routes/simple-2 routes/tmpl-1 subscriptions/sub-3 applications/arTestPullApplication sites/site-pull sites/site-push files/outbound-drop files/delivered files/subscription myself accounts/arTestAccount " ] \
    && pass "finds by name; deletes the routes, subscription, application, sites, then the folders, then the account" || fail "order: ${ORDER}"
echo "${D}" | grep -qE 'sub-else|site-other|site-else|route-else' && fail "deleted something that is not the test account's" || pass "leaves other accounts' objects and unrelated ones alone"
run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json" x 404
if [[ "${OUT}" == *"does not exist (HTTP 404)"* ]] && ! calls | grep -q '^DELETE .*/accounts/'; then pass "an account that is already gone is reported, not deleted"; else fail "missing account: $(echo "${OUT}" | tail -n 3)"; fi
calls | grep -q '^HEAD .*/accounts/arTestAccount$' && pass "checks that the account exists first" || fail "no existence check"
echo '{"version":"5.5-20260924","result":[]}' > "${WORK}/version_no_objects.json"
run 99.cleanup_DELETE.sh "${WORK}/version_no_objects.json"
[[ "${OUT}" == *"No routes to delete"* ]] && [[ "${OUT}" == *"No sites to delete"* ]] && calls | tail -n 1 | grep -q '^DELETE .*/accounts/arTestAccount$' && pass "nothing found: says so, and still deletes the account" || fail "no-objects case: ${OUT}"
# The folders are emptied before they are removed
run 99.cleanup_DELETE.sh "${WORK}/version_and_files.json"
F=$(calls | grep '^DELETE' | sed 's#.*/api/v2.0/##' | grep '^files/' | tr '\n' ' ')
[ "${F}" = "files/outbound-drop/file_01102026.trigger files/outbound-drop/pull_test_1.txt files/outbound-drop files/delivered/file_01102026.trigger files/delivered/pull_test_1.txt files/delivered files/subscription/file_01102026.trigger files/subscription/pull_test_1.txt files/subscription " ] \
    && pass "empties each folder (files, not sub-folders) and then removes it" || fail "folder deletes: ${F}"
# Without a password the folders stay, and the account still goes
mv "${RUN}/settings.local.sh" "${RUN}/settings.local.sh.off"
run 99.cleanup_DELETE.sh "${WORK}/version_and_objects.json"
if [[ "${OUT}" == *"folders are left in place"* ]] && ! calls | grep -q 'DELETE .*files/' && calls | tail -n 1 | grep -q '^DELETE .*/accounts/arTestAccount$'; then pass "no password: the folders are left in place, the account is still deleted"; else fail "no-password case"; fi
mv "${RUN}/settings.local.sh.off" "${RUN}/settings.local.sh"
printf 'export AR_ID_TEMPLATE=left-over\n' > "${RUN}/state.local.sh"
run 99.cleanup_DELETE.sh "${WORK}/version_no_objects.json"
[ ! -f "${RUN}/state.local.sh" ] && pass "removes the saved ids" || fail "state file left behind"

echo
echo "=== 00.run_all.sh ==="
# One fixture that answers every call the steps make: version, listings, ids
cat > "${WORK}/everything.json" <<JSON
{
  "version": "5.5-20260924",
  "files": [
    {"fileName": "file_01102026.trigger", "isRegularFile": true, "lastModifiedTime": 200, "size": 48},
    {"fileName": "pull_test_1.txt_PULLED", "isRegularFile": true, "lastModifiedTime": 150, "size": 32}],
  "result": [
    {"id": "comp-4",   "name": "arTestPullPackage",    "account": "arTestAccount"},
    {"id": "simple-2", "name": "arTestSendToPushSite", "account": "arTestAccount"},
    {"id": "tmpl-1",   "name": "arTestPackageTemplate"},
    {"id": "sub-3",    "account": "arTestAccount", "application": "arTestPullApplication"},
    {"id": "app-5",    "name": "arTestPullApplication"},
    {"id": "site-pull","name": "arTestPullSite", "account": "arTestAccount"},
    {"id": "site-push","name": "arTestPushSite", "account": "arTestAccount"}]
}
JSON
rm -f "${RUN}/state.local.sh"
master() { OUT=$(cd "${RUN}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/everything.json" STUB_CURL_POST_BODY="${WORK}/operation.json" \
           STUB_CURL_LOCATION_ID="new-id" STUB_CURL_STATUS="${STATUS:-201}" STUB_CURL_PRINT_CODE=1 STUB_CURL_CSRF="csrf-abc" bash ./00.run_all.sh "$@" 2>&1); RC=$?; }
STATUS=201 master
[ "${RC}" -eq 0 ] && pass "runs all the steps and exits 0" || fail "exit ${RC}: $(echo "${OUT}" | tail -n 5)"
STEPS_SEEN=$(echo "${OUT}" | sed -n 's/^=== Step \([0-9]*\) of \([0-9]*\): \(.*\) ===$/\1\/\2 \3/p' | tr '\n' ',')
EXPECT_STEPS="1/13 01.accounts_POST.sh,2/13 02.sites_POST_pull.sh,3/13 03.sites_POST_push.sh,4/13 04.files_POST_folders.sh,5/13 05.files_upload_POST.sh,6/13 06.routes_POST_template.sh,7/13 07.routes_POST_simple.sh,8/13 08.applications_POST.sh,9/13 09.subscriptions_POST.sh,10/13 10.routes_POST_composite.sh,11/13 11.transfers_pull_POST.sh,12/13 12.files_PUT_triggerfile.sh,13/13 13.files_GET_result.sh,"
[ "${STEPS_SEEN}" = "${EXPECT_STEPS}" ] && pass "runs the 13 numbered steps in order, and neither itself nor the cleanup" || fail "steps: ${STEPS_SEEN}"
PAUSES=$(echo "${OUT}" | awk '/^=== Step/ {step=$3} /^Pausing/ {print step}' | tr '\n' ' ')
[ "${PAUSES}" = "11 12 " ] && pass "pauses after step 11 and after step 12, and nowhere else" || fail "pauses came after steps: ${PAUSES}"
[[ "${OUT}" == *"All 13 steps finished"* ]] && [[ "${OUT}" != *"Cleanup: 99"* ]] && pass "without --cleanup it leaves everything in place" || fail "unexpected cleanup"
STATUS=201 master --cleanup
[ "${RC}" -eq 0 ] && [[ "${OUT}" == *"=== Cleanup: 99.cleanup_DELETE.sh ==="* ]] && pass "--cleanup runs the cleanup at the end" || fail "--cleanup (exit ${RC})"
STATUS=500 master
if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *"Stopped at step 1 of 13: 01.accounts_POST.sh failed"* ]] && [[ "${OUT}" != *"Step 2 of 13"* ]]; then pass "stops at the first step whose output shows an HTTP error, and runs nothing after it"; else fail "failure case (exit ${RC})"; fi
STATUS=201 master --bogus
[ "${RC}" -eq 2 ] && pass "an unknown option is refused" || fail "--bogus exit ${RC}"

echo
echo "=== Guard rails ==="
for s in 01.accounts_POST.sh 02.sites_POST_pull.sh 03.sites_POST_push.sh 04.files_POST_folders.sh 05.files_upload_POST.sh 06.routes_POST_template.sh 07.routes_POST_simple.sh 08.applications_POST.sh 09.subscriptions_POST.sh 10.routes_POST_composite.sh 11.transfers_pull_POST.sh 12.files_PUT_triggerfile.sh 13.files_GET_result.sh 99.cleanup_DELETE.sh; do
    run "${s}" "${SERVER_OLD}"
    if [ "${RC}" -eq 0 ] && [[ "${OUT}" == *SKIPPED* ]] && ! echo "${OUT}" | grep -qE '^METHOD: (POST|DELETE)'; then
        pass "${s}: skipped, and sends nothing, on an older server"
    else
        fail "${s}: acted on an older server (exit ${RC})"
    fi
done

mv "${RUN}/settings.local.sh" "${RUN}/settings.local.sh.off"
for s in 01.accounts_POST.sh 02.sites_POST_pull.sh 03.sites_POST_push.sh 04.files_POST_folders.sh 05.files_upload_POST.sh 12.files_PUT_triggerfile.sh 13.files_GET_result.sh; do
    run "${s}" "${SERVER_NEW}"
    if [ "${RC}" -eq 1 ] && [[ "${OUT}" == *AR_ACCOUNT_PASSWORD* ]] && ! echo "${OUT}" | grep -qE '^METHOD: POST'; then
        pass "${s}: stops and sends nothing when no password is set"
    else
        fail "${s}: ran without a password (exit ${RC})"
    fi
done

echo
echo "=== Pairs ==="
# Tracked files only: a developer's own settings.local.* is not part of the repository
for f in $(cd "${REPO}" && git ls-files "${FEATURE}/*.sh"); do
    [ -f "${REPO}/${f%.sh}.bat" ] || fail "no bat twin: $(basename "$f")"
done
pass "every script has a bat twin"

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_feature_trigger_route_pull: PASS"; else echo "test_feature_trigger_route_pull: FAIL"; fi
exit "${FAILED}"
