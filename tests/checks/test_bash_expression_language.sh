#!/bin/bash
# ==============================================================================
# Run the 14.ExpressionLanguage examples against a stub curl and check what each
# one sends: which objects it creates, that the Expression Language reaches the
# server exactly as written, and that every object it created is deleted again.
#
# The expressions are the point of these examples, and they are easy to damage in
# a shell script: ${...} is expanded by the shell unless it is escaped, a
# backslash in a JSON string must be doubled, and a regular expression has
# backslashes of its own. So the exact string that is sent is asserted for each.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"

WORK="${TESTS_DIR}/output/bash_expression_language"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
cp -R "${REPO}/Admin/API 2.0/bash/14.ExpressionLanguage" "${WORK}/admin/"
EL_DIR="${WORK}/admin/14.ExpressionLanguage"
BASE="https://st.example.com:8444/api/v2.0"

# The id the scripts look a created object up by name for, to delete it
printf '{"result":[{"id":"RID1"}]}\n' > "${WORK}/ids.json"

run() {
    OUT=$(cd "${EL_DIR}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/ids.json" STUB_CURL_STATUS=201 \
          bash "./$1" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
payloads() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | while read -r b; do printf '%s' "${b}" | base64 -d; echo; done; }
count() { calls | grep -c "^$1 $2"; }
# every object created is looked up by name and deleted again: one DELETE per POST
balanced() { expect "$1: every object it creates is deleted again" "$(count POST "${BASE}/$2")/$(count DELETE "${BASE}/$2/")" "$3/$3"; }
# the names it creates, in order, from the bodies it sends
created() { payloads | jq -c -s 'map(.name)'; }

echo "=== 01.loginRestrictionPolicy_sessionExpression.sh ==="
run 01.loginRestrictionPolicy_sessionExpression.sh
expect "01: exit 0" "${RC}" "0"
expect "01: creates a policy, patches a rule in, reads it, deletes it" "$(calls)" \
"POST ${BASE}/loginRestrictionPolicies
PATCH ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit
GET ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit
DELETE ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit"
expect "01: the policy type" "$(payload 1 | jq -r .type)" "ALLOW_THEN_DENY"
expect "01: the rule is added at /rules/0" "$(payload 2 | jq -r '.[0] | [.op, .path] | join(" ")')" "add /rules/0"
expect "01: the \${...} expression arrives as written, not expanded by the shell" \
  "$(payload 2 | jq -r '.[0].value.expression')" '${currentSessions <= 3}'
expect "01: the rule allows, for any address" "$(payload 2 | jq -c '.[0].value | [.type, .clientAddress, .isEnabled]')" '["ALLOW","*",true]'

echo
echo "=== 02.routes_condition_EL.sh ==="
run 02.routes_condition_EL.sh
expect "02: exit 0" "${RC}" "0"
expect "02: the routes it creates" "$(created)" '["ZZTEST_EL_route_disabled","ZZTEST_EL_route_hasEmail","ZZTEST_EL_route_bytesGE20"]'
balanced 02 routes 3
expect "02: the conditions arrive as written, as EL conditions" \
  "$(payloads | jq -c -s 'map([.conditionType, .condition])')" \
  '[["EL","${account.disabled != '"'"'0'"'"'}"],["EL","${!empty account.email}"],["EL","${transfer.transferredBytes ge 20}"]]'

echo
echo "=== 03.routes_step_fileFilterExpression_glob.sh ==="
run 03.routes_step_fileFilterExpression_glob.sh
expect "03: exit 0" "${RC}" "0"
expect "03: the routes it creates" "$(created)" '["ZZTEST_EL_glob_anyXml","ZZTEST_EL_glob_fooDotTwoAny","ZZTEST_EL_glob_singleDigit","ZZTEST_EL_glob_notDigit"]'
balanced 03 routes 4
expect "03: the glob patterns, each marked GLOB" \
  "$(payloads | jq -c -s 'map(.steps[0] | [.fileFilterExpression, .fileFilterExpressionType])')" \
  '[["*.xml","GLOB"],["foo.??","GLOB"],["*.[0-9]","GLOB"],["*.[!0-9]","GLOB"]]'

echo
echo "=== 04.routes_step_fileFilterExpression_regexp.sh ==="
run 04.routes_step_fileFilterExpression_regexp.sh
expect "04: exit 0" "${RC}" "0"
expect "04: the routes it creates" "$(created)" '["ZZTEST_EL_regexp_xmlOrTxt","ZZTEST_EL_regexp_caseInsensitive","ZZTEST_EL_regexp_negativeLookahead"]'
balanced 04 routes 3
# jq -c shows a backslash of the value as \\ : one backslash in the pattern
expect "04: the regular expressions keep their single backslash, each marked REGEXP" \
  "$(payloads | jq -c -s 'map(.steps[0] | [.fileFilterExpression, .fileFilterExpressionType])')" \
  '[[".*\\.(xml|txt)","REGEXP"],["(?i)data\\.xml","REGEXP"],["^(?!.*__TID\\d{6}__[A-Za-z0-9]{16}).*$","REGEXP"]]'

echo
echo "=== 05.routes_step_condition_matches_backslashDoubling.sh ==="
run 05.routes_step_condition_matches_backslashDoubling.sh
expect "05: exit 0" "${RC}" "0"
expect "05: the two routes it creates" "$(created)" '["ZZTEST_EL_doubled","ZZTEST_EL_single"]'
balanced 05 routes 2
# The point of the example: inside matches('...') the expression language reads a backslash
# as an escape, so a literal backslash needs two in the value. Both are sent as the script writes them.
expect "05: the doubled form sends two backslashes in the value" \
  "$(payload 1 | jq -r .condition)" "\${transfer.target.matches('.*\\\\.txt')}"
expect "05: the single form sends one" "$(payload 2 | jq -r .condition)" "\${transfer.target.matches('.*\\.txt')}"

echo
echo "=== 06.routes_step_renameExpression.sh ==="
run 06.routes_step_renameExpression.sh
expect "06: exit 0" "${RC}" "0"
expect "06: the routes it creates" "$(created)" '["ZZTEST_EL_rename_timestamped","ZZTEST_EL_rename_randomId","ZZTEST_EL_rename_accountName"]'
balanced 06 routes 3
expect "06: the rename expressions arrive as written" \
  "$(payloads | jq -c -s 'map(.steps[0].postTransformationActionRenameAsExpression)')" \
  '["${basename(transfer.target)}-${date('"'"'yyyyMMdd_HHmmss'"'"')}${extension(transfer.target)}","${basename(transfer.target)}-${random()}.${extension(transfer.target)}","${account.name}_${basename(transfer.target)}"]'

echo
echo "=== 07.transferSites_downloadPattern.sh ==="
run 07.transferSites_downloadPattern.sh
expect "07: exit 0" "${RC}" "0"
expect "07: the sites it creates" "$(created)" '["ZZTEST_EL_dlpattern_anyXml","ZZTEST_EL_dlpattern_singleDigit","ZZTEST_EL_dlpattern_xmlOrTxt"]'
balanced 07 sites 3
expect "07: the download patterns, each with its type" \
  "$(payloads | jq -c -s 'map([.downloadPattern, .downloadPatternType])')" \
  '[["*.xml","glob"],["*.[0-9]","glob"],[".*\\.(xml|txt)","regex"]]'
expect "07: the sites point at the server of the settings, never at a host written in the script" \
  "$(payloads | jq -r -s 'map(.host) | unique | join(",")')" "st.example.com"

echo
echo "=== 08.transferSites_dynamicProperties.sh ==="
run 08.transferSites_dynamicProperties.sh
expect "08: exit 0" "${RC}" "0"
expect "08: creates one site, reads it, looks it up and deletes it" "$(calls)" \
"POST ${BASE}/sites
GET ${BASE}/sites?name=ZZTEST_EL_dynamicSite&fields=name,host,downloadPattern
GET ${BASE}/sites?name=ZZTEST_EL_dynamicSite&fields=id
DELETE ${BASE}/sites/RID1"
expect "08: host and download pattern are the \${DXAGENT_TRANSFERSAPI_...} properties, not expanded by the shell" \
  "$(payload 1 | jq -r '[.host, .downloadPattern] | join(" ")')" '${DXAGENT_TRANSFERSAPI_SERVER} ${DXAGENT_TRANSFERSAPI_FILE}'

echo
echo "=== every script says what it really uses ==="
# They send Basic authentication on every call and never log in or out, so /myself is not an API they use
BAD=$(grep -l "APIs used - /myself" "${REPO}/Admin/API 2.0/bash/14.ExpressionLanguage/"*.sh)
expect "none of them claims to use /myself" "${BAD}" ""

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_expression_language: PASS"
else
    echo "test_bash_expression_language: FAIL"
fi
exit "${FAILED}"
