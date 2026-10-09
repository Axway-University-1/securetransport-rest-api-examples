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
# The other half is what the scripts do with the answers. Each one:
#   - looks first for an object of each name it is going to create, and stops
#     with exit 2, creating and deleting nothing, when one is there (it only ever
#     deletes what it created)
#   - checks the status of every call and exits 1 on a refusal
#   - deletes what it created by the id in the Location of its own POST, never by
#     looking a name up, also after a refusal (the cleanup is an EXIT trap)
#   - exits 0 only when every call answered what was expected
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_expression_language"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }

# curl: the stub, with a status of its own for each method and a different Location id for each POST
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
cp -R "${REPO}/Admin/API 2.0/bash/14.ExpressionLanguage" "${WORK}/admin/"
EL_DIR="${WORK}/admin/14.ExpressionLanguage"
BASE="https://st.example.com:8444/api/v2.0"

# What every GET answers unless a test says otherwise: a list with an object in it that no script is looking for
printf '{"result":[{"id":"RID1","name":"some_other_object"}]}\n' > "${WORK}/ids.json"
printf '{"result":[]}\n' > "${WORK}/empty.json"

# run SCRIPT: GET_BODY is what the GETs answer; ST_POST, ST_GET, ST_DELETE the status of each method (201, 200, 204);
# ST_POST_SEQ and ST_GET_SEQ a status for each call in turn; SEQUENCE a folder of answers for the GETs in turn;
# LOC_PREFIX the Location ids the POSTs answer with (ID gives ID1, ID2, ...; empty gives no Location at all)
run() {
    rm -f "${WORK}/counter."*
    OUT=$(cd "${EL_DIR}" && PATH="${WORK}/bin:${PATH}" STUB_COUNTER="${WORK}/counter" STUB_CURL_PRINT_CODE=1 \
          STUB_LOCATION_PREFIX="${LOC_PREFIX-ID}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/ids.json}" STUB_CURL_GET_SEQUENCE="${SEQUENCE:-}" \
          STUB_STATUS_GET="${ST_GET:-200}" STUB_STATUS_POST="${ST_POST:-201}" STUB_STATUS_PATCH=204 STUB_STATUS_DELETE="${ST_DELETE:-204}" \
          STUB_STATUS_POST_SEQ="${ST_POST_SEQ:-}" STUB_STATUS_GET_SEQ="${ST_GET_SEQ:-}" \
          bash "./$1" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
payloads() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | while read -r b; do printf '%s' "${b}" | base64 -d; echo; done; }
count() { calls | grep -c "^$1 $2"; }
# the names it creates, in order, from the bodies it sends
created() { payloads | jq -c -s 'map(.name)'; }
# every object created is deleted again, each by the id its own POST answered with: ID1 for the first, ID2 for the second...
balanced() {
    local kind="$2" n="$3" want="" i
    for i in $(seq 1 "${n}"); do want="${want}DELETE ${BASE}/${kind}/ID${i}"$'\n'; done
    expect "$1: every object it creates is deleted again, each by the id of its own POST" "$(count POST "${BASE}/${kind}"):$(calls | grep '^DELETE ')" "${n}:${want%$'\n'}"
}
# every call looks for the name before creating it
lookups() { expect "$1: looks for each name before it creates anything" "$(calls | head -"$3" | grep -c "^GET ${BASE}/$2?name=.*&fields=id,name$")" "$3"; }

# The scripts of this folder: file, what they create (the path, the names, in order)
EL_01=01.loginRestrictionPolicy_sessionExpression.sh
EL_02=02.routes_condition_EL.sh
EL_03=03.routes_step_fileFilterExpression_glob.sh
EL_04=04.routes_step_fileFilterExpression_regexp.sh
EL_05=05.routes_step_condition_matches_backslashDoubling.sh
EL_06=06.routes_step_renameExpression.sh
EL_07=07.transferSites_downloadPattern.sh
EL_08=08.transferSites_dynamicProperties.sh

echo "=== 01.loginRestrictionPolicy_sessionExpression.sh ==="
run ${EL_01}
expect "01: exit 0" "${RC}" "0"
expect "01: looks for the policy, creates it, patches a rule in, reads it, deletes it" "$(calls)" \
"GET ${BASE}/loginRestrictionPolicies?name=ZZTEST_EL_sessionLimit&fields=id,name
POST ${BASE}/loginRestrictionPolicies
PATCH ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit
GET ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit
DELETE ${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit"
expect "01: the policy type" "$(payload 1 | jq -r .type)" "ALLOW_THEN_DENY"
expect "01: the rule is added at /rules/0" "$(payload 2 | jq -r '.[0] | [.op, .path] | join(" ")')" "add /rules/0"
expect "01: the \${...} expression arrives as written, not expanded by the shell" \
  "$(payload 2 | jq -r '.[0].value.expression')" '${currentSessions <= 3}'
expect "01: the rule allows, for any address" "$(payload 2 | jq -c '.[0].value | [.type, .clientAddress, .isEnabled]')" '["ALLOW","*",true]'
has "01: prints the HTTP code of the creation" "HTTP 201"
printf '{"result":[{"id":"OLD1","name":"zztest_el_SESSIONLIMIT"}]}\n' > "${WORK}/old_policy.json"
GET_BODY="${WORK}/old_policy.json" run ${EL_01}
expect "01: a policy of that name (in any case) is there already: exit 2, nothing created or deleted" "${RC}:$(calls | grep -vc '^GET ')" "2:0"
has "01: says which one is there" "zztest_el_SESSIONLIMIT (id OLD1)"
ST_POST=400 run ${EL_01}
expect "01: a refused creation is exit 1, and nothing is deleted that was not created" "${RC}:$(count DELETE "${BASE}")" "1:0"
ST_DELETE=500 run ${EL_01}
expect "01: a delete that fails is exit 1" "${RC}" "1"
SEQUENCE=
ST_GET_SEQ="200 500" run ${EL_01}
expect "01: a read that fails is exit 1, and the policy it created is deleted all the same" "${RC}:$(count DELETE "${BASE}/loginRestrictionPolicies/ZZTEST_EL_sessionLimit")" "1:1"

echo
echo "=== 02.routes_condition_EL.sh ==="
run ${EL_02}
expect "02: exit 0" "${RC}" "0"
expect "02: the routes it creates" "$(created)" '["ZZTEST_EL_route_disabled","ZZTEST_EL_route_hasEmail","ZZTEST_EL_route_bytesGE20"]'
balanced 02 routes 3
lookups 02 routes 3
expect "02: the conditions arrive as written, as EL conditions" \
  "$(payloads | jq -c -s 'map([.conditionType, .condition])')" \
  '[["EL","${account.disabled != '"'"'0'"'"'}"],["EL","${!empty account.email}"],["EL","${transfer.transferredBytes ge 20}"]]'
printf '{"result":[{"id":"OLD1","name":"ZZTEST_EL_route_hasEmail"}]}\n' > "${WORK}/old_route.json"
GET_BODY="${WORK}/old_route.json" run ${EL_02}
expect "02: a route of one of the names is there already: exit 2, nothing created, nothing deleted" "${RC}:$(calls | grep -vc '^GET ')" "2:0"
has "02: and it says which one is there" "ZZTEST_EL_route_hasEmail (id OLD1)"
ST_POST_SEQ="201 400" run ${EL_02}
expect "02: the second creation is refused: exit 1" "${RC}" "1"
expect "02: the third is not tried, and the first is deleted all the same, by its own id" "$(count POST "${BASE}/routes")/$(calls | grep '^DELETE ')" "2/DELETE ${BASE}/routes/ID1"
has "02: the server's reason is printed" "HTTP 400"
ST_DELETE=500 run ${EL_02}
expect "02: deletes that fail are exit 1, and all three are tried" "${RC}:$(count DELETE "${BASE}/routes/")" "1:3"
ST_GET_SEQ="200 200 200 500" run ${EL_02}
expect "02: a read that fails is exit 1, and the three routes are deleted all the same" "${RC}:$(count DELETE "${BASE}/routes/")" "1:3"

echo
echo "=== 03.routes_step_fileFilterExpression_glob.sh ==="
run ${EL_03}
expect "03: exit 0" "${RC}" "0"
expect "03: the routes it creates" "$(created)" '["ZZTEST_EL_glob_anyXml","ZZTEST_EL_glob_fooDotTwoAny","ZZTEST_EL_glob_singleDigit","ZZTEST_EL_glob_notDigit"]'
balanced 03 routes 4
lookups 03 routes 4
expect "03: the glob patterns, each marked GLOB" \
  "$(payloads | jq -c -s 'map(.steps[0] | [.fileFilterExpression, .fileFilterExpressionType])')" \
  '[["*.xml","GLOB"],["foo.??","GLOB"],["*.[0-9]","GLOB"],["*.[!0-9]","GLOB"]]'
printf '{"result":[{"id":"OLD1","name":"ZZTEST_EL_glob_notDigit"}]}\n' > "${WORK}/old_route.json"
GET_BODY="${WORK}/old_route.json" run ${EL_03}
expect "03: a route of one of the names is there already: exit 2, nothing created or deleted" "${RC}:$(calls | grep -vc '^GET ')" "2:0"
ST_POST=500 run ${EL_03}
expect "03: a refused creation is exit 1, with nothing to delete" "${RC}:$(count DELETE "${BASE}")" "1:0"

echo
echo "=== 04.routes_step_fileFilterExpression_regexp.sh ==="
run ${EL_04}
expect "04: exit 0" "${RC}" "0"
expect "04: the routes it creates" "$(created)" '["ZZTEST_EL_regexp_xmlOrTxt","ZZTEST_EL_regexp_caseInsensitive","ZZTEST_EL_regexp_negativeLookahead"]'
balanced 04 routes 3
lookups 04 routes 3
# jq -c shows a backslash of the value as \\ : one backslash in the pattern
expect "04: the regular expressions keep their single backslash, each marked REGEXP" \
  "$(payloads | jq -c -s 'map(.steps[0] | [.fileFilterExpression, .fileFilterExpressionType])')" \
  '[[".*\\.(xml|txt)","REGEXP"],["(?i)data\\.xml","REGEXP"],["^(?!.*__TID\\d{6}__[A-Za-z0-9]{16}).*$","REGEXP"]]'
ST_POST_SEQ="201 201 400" run ${EL_04}
expect "04: the third creation is refused: exit 1, and the two it created are deleted by their ids" "${RC}:$(calls | grep '^DELETE ' | tr '\n' ' ')" "1:DELETE ${BASE}/routes/ID1 DELETE ${BASE}/routes/ID2 "

echo
echo "=== 05.routes_step_condition_matches_backslashDoubling.sh ==="
run ${EL_05}
expect "05: exit 0" "${RC}" "0"
expect "05: the two routes it creates" "$(created)" '["ZZTEST_EL_doubled","ZZTEST_EL_single"]'
balanced 05 routes 2
lookups 05 routes 2
# The point of the example: inside matches('...') the expression language reads a backslash
# as an escape, so a literal backslash needs two in the value. Both are sent as the script writes them.
expect "05: the doubled form sends two backslashes in the value" \
  "$(payload 1 | jq -r .condition)" "\${transfer.target.matches('.*\\\\.txt')}"
expect "05: the single form sends one" "$(payload 2 | jq -r .condition)" "\${transfer.target.matches('.*\\.txt')}"
printf '{"result":[{"id":"OLD1","name":"ZZTEST_EL_single"}]}\n' > "${WORK}/old_route.json"
GET_BODY="${WORK}/old_route.json" run ${EL_05}
expect "05: a route of one of the names is there already: exit 2, nothing created or deleted" "${RC}:$(calls | grep -vc '^GET ')" "2:0"
ST_POST_SEQ="201 409" run ${EL_05}
expect "05: the second is refused: exit 1, the first is deleted by its id" "${RC}:$(calls | grep '^DELETE ')" "1:DELETE ${BASE}/routes/ID1"

echo
echo "=== 06.routes_step_renameExpression.sh ==="
run ${EL_06}
expect "06: exit 0" "${RC}" "0"
expect "06: the routes it creates" "$(created)" '["ZZTEST_EL_rename_timestamped","ZZTEST_EL_rename_randomId","ZZTEST_EL_rename_accountName"]'
balanced 06 routes 3
lookups 06 routes 3
expect "06: the rename expressions arrive as written" \
  "$(payloads | jq -c -s 'map(.steps[0].postTransformationActionRenameAsExpression)')" \
  '["${basename(transfer.target)}-${date('"'"'yyyyMMdd_HHmmss'"'"')}${extension(transfer.target)}","${basename(transfer.target)}-${random()}.${extension(transfer.target)}","${account.name}_${basename(transfer.target)}"]'

echo
echo "=== 07.transferSites_downloadPattern.sh ==="
run ${EL_07}
expect "07: exit 0" "${RC}" "0"
expect "07: the sites it creates" "$(created)" '["ZZTEST_EL_dlpattern_anyXml","ZZTEST_EL_dlpattern_singleDigit","ZZTEST_EL_dlpattern_xmlOrTxt"]'
balanced 07 sites 3
lookups 07 sites 3
expect "07: the download patterns, each with its type" \
  "$(payloads | jq -c -s 'map([.downloadPattern, .downloadPatternType])')" \
  '[["*.xml","glob"],["*.[0-9]","glob"],[".*\\.(xml|txt)","regex"]]'
expect "07: the sites point at the server of the settings, never at a host written in the script" \
  "$(payloads | jq -r -s 'map(.host) | unique | join(",")')" "st.example.com"
ST_POST_SEQ="201 400" run ${EL_07}
expect "07: the second site is refused (the account john is not there, say): exit 1, the first is deleted by its id" "${RC}:$(calls | grep '^DELETE ')" "1:DELETE ${BASE}/sites/ID1"

echo
echo "=== 08.transferSites_dynamicProperties.sh ==="
run ${EL_08}
expect "08: exit 0" "${RC}" "0"
expect "08: looks for the site, creates one, reads it, deletes it by the id of its POST" "$(calls)" \
"GET ${BASE}/sites?name=ZZTEST_EL_dynamicSite&fields=id,name
POST ${BASE}/sites
GET ${BASE}/sites?name=ZZTEST_EL_dynamicSite&fields=name,host,downloadPattern
DELETE ${BASE}/sites/ID1"
expect "08: host and download pattern are the \${DXAGENT_TRANSFERSAPI_...} properties, not expanded by the shell" \
  "$(payload 1 | jq -r '[.host, .downloadPattern] | join(" ")')" '${DXAGENT_TRANSFERSAPI_SERVER} ${DXAGENT_TRANSFERSAPI_FILE}'
ST_POST=400 run ${EL_08}
expect "08: a refusal is exit 1, and no delete is sent for what was never created" "${RC}:$(count DELETE "${BASE}")" "1:0"
printf '{"result":[{"id":"OLD1","name":"zztest_el_dynamicsite"}]}\n' > "${WORK}/old_site.json"
GET_BODY="${WORK}/old_site.json" run ${EL_08}
expect "08: a site of that name is there already: exit 2, nothing created or deleted" "${RC}:$(calls | grep -vc '^GET ')" "2:0"
# No Location in the answer: the id is looked up by the exact name, which is free before the script, so the object found is its own
rm -rf "${WORK}/seq" && mkdir -p "${WORK}/seq"
printf '{"result":[]}\n' > "${WORK}/seq/1.json"
printf '{"result":[{"id":"FOUND1","name":"ZZTEST_EL_dynamicSite"}]}\n' > "${WORK}/seq/2.json"
LOC_PREFIX= SEQUENCE="${WORK}/seq" run ${EL_08}
expect "08: a creation that answers no Location is looked up by its name, and that id is deleted" "${RC}:$(calls | grep '^DELETE ')" "0:DELETE ${BASE}/sites/FOUND1"
SEQUENCE=
ST_GET_SEQ="200 500" run ${EL_08}
expect "08: a read that fails is exit 1, and the site is deleted all the same" "${RC}:$(calls | grep '^DELETE ')" "1:DELETE ${BASE}/sites/ID1"

echo
echo "=== the cleanup is by id, and an interruption runs it ==="
for s in ${EL_02} ${EL_03} ${EL_04} ${EL_05} ${EL_06} ${EL_07} ${EL_08}; do
    expect "${s}: no delete looks a name up (no jq .result[0].id)" "$(grep -c 'result\[0\]' "${REPO}/Admin/API 2.0/bash/14.ExpressionLanguage/${s}")" "0"
done
for s in ${EL_01} ${EL_02} ${EL_03} ${EL_04} ${EL_05} ${EL_06} ${EL_07} ${EL_08}; do
    expect "${s}: the cleanup is an EXIT trap, and INT and TERM end the script through it" \
      "$(grep -c "^trap " "${REPO}/Admin/API 2.0/bash/14.ExpressionLanguage/${s}")" "3"
done

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
