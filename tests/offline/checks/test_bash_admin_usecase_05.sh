#!/bin/bash
# ==============================================================================
# Run the Admin use case 05-changing-an-object against a stub curl, and check the calls each script
# makes: method, URL, the exact body of every PATCH and PUT (a number is not quoted, a boolean is not quoted, a list is
# addressed by position), headers, what it does with the answer, and its exit code.
#
# 01 makes the account and the route (a HEAD first, then a POST of each, the route's id from the Location header);
# 02 reads both and keeps a copy; 03 to 08 are one PATCH per case, shown with the field before and after, and exit 1 when
# the server does not answer as documented; 09 and 10 PUT the whole route and a fragment; 11 saves, changes and puts back
# a server option and refuses to start over a saved copy; 99 puts the option back, deletes the route and the account,
# and can be run twice; 00 stops at the first failing step and still cleans up.
#
# The stub serves the GETs of a case from a numbered sequence (the value before, the value after), so a test says what the
# server "answers" and the script's own checks are what is under test.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_05"
rm -rf "${WORK:?}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl_by_method" && chmod +x "${WORK}/bin/curl_by_method"
# curl: the answer body of a PATCH or a PUT (STUB_BODY_WRITE: stub_curl_by_method's own STUB_BODY_OTHER would answer a HEAD with it too), then the wrapper
cat > "${WORK}/bin/curl" <<'STUB'
#!/bin/bash
prev=""; method=GET
for a in "$@"; do [ "${prev}" = "-X" ] && method="${a}"; prev="${a}"; done
case "${method}" in PATCH|PUT) [ -n "${STUB_BODY_WRITE}" ] && [ -f "${STUB_BODY_WRITE}" ] && cat "${STUB_BODY_WRITE}" ;; esac
exec "$(dirname "$0")/curl_by_method" "$@"
STUB
chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp -R "${UC_ROOT}/." "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
UC="${WORK}/tree/UseCases/05-changing-an-object"
ACC="${BASE}/accounts/example_chg"
RT="${BASE}/routes/rid1"
OPT="AddressBook.Limit.MaxDisplayEntries"
STATE_FILES="state.local.route_id state.local.option.json state.local.account.json state.local.route.json state.local.csrf session.cookie.jar"
clear_state() { local f; for f in ${STATE_FILES}; do rm -f "${UC:?}/${f}"; done; }
start_state() { clear_state; echo tok123 > "${UC}/state.local.csrf"; echo rid1 > "${UC}/state.local.route_id"; }
echo '{"loginName":"admin"}' > "${WORK}/me.json"
echo '{"resultSet":{"returnCount":0},"result":[]}' > "${WORK}/noroute.json"
echo '{"resultSet":{"returnCount":1},"result":[{"id":"r7","name":"example_chg_route"}]}' > "${WORK}/oneroute.json"
echo '{"message":"Error validating request","validationErrors":["Incorrect JSON format"]}' > "${WORK}/err.json"

# SEQ_DIR: the folder of numbered answers the GETs get, one after another. STUB_STATUS_<METHOD>_SEQ: the status of each call of a method.
run() {
    local rel="$1"; shift
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/me.json}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_GET_SEQUENCE="${SEQ_DIR:-}" \
          STUB_BODY_WRITE="${BODY_OTHER:-}" STUB_CURL_STATUS="${STATUS:-200}" STUB_COUNTER="${WORK}/ctr" STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
    rm -f "${WORK}"/ctr.*
}
urun() { touch "${UC}/session.cookie.jar"; run "$@"; }
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | wc -l | tr -d ' '; }
# the calls after the check for a session (st_session starts with a GET of /myself when there is a jar)
ucalls() { calls | sed '1{/^GET .*\/myself$/d;}' | tr '\n' ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
npayloads() { printf '%s\n' "${OUT}" | grep -c '^PAYLOAD_B64: '; }
bodies() { local i n; n=$(npayloads); for ((i = 1; i <= n; i++)); do payload "$i" | jq -c .; done; }
firsts() { bodies | jq -r '.[0] | "\(.op) \(.path)"' | tr '\n' ';'; }
# cases N URL: a HEAD of URL, then N times a case (GET, PATCH, GET) on it
cases() { local s="HEAD $2 " i; for ((i = 0; i < $1; i++)); do s+="GET $2 PATCH $2 GET $2 "; done; printf '%s' "${s}"; }
hdrs_of() { printf '%s\n' "${OUT}" | awk -v M="$1" '/^HEADER:/ {b = b $0 "\n"} /^METHOD:/ {if ($2 == M) r = b; b = ""} END {printf "%s", r}' | sed 's/^HEADER: //'; }

# mk_seq DIR BASE PREFIX EDIT...: the answers of the GETs (the first one is the check of the session). PREFIX reads of BASE first (reads before the first case), then each EDIT is
# one case: its "before" is the state so far, its "after" is the state with the jq EDIT applied ("." changes nothing); the word READ
# is one more read of the state so far, between cases.
mk_seq() {
    local dir="$1" cur="$2" pre="$3" n=0 i edit; shift 3
    rm -rf "${dir:?}"; mkdir -p "${dir}"
    echo '{"loginName":"admin"}' > "${dir}/1.json"; n=1   # the first GET is the session check
    for ((i = 0; i < pre; i++)); do n=$((n + 1)); printf '%s\n' "${cur}" > "${dir}/${n}.json"; done
    for edit in "$@"; do
        n=$((n + 1)); printf '%s\n' "${cur}" > "${dir}/${n}.json"
        if [ "${edit}" = "READ" ]; then continue; fi
        cur=$(printf '%s' "${cur}" | jq -c "${edit}")
        n=$((n + 1)); printf '%s\n' "${cur}" > "${dir}/${n}.json"
    done
    SEQ_DIR="${dir}"
}
# seq_files DIR BODY...: the GETs answer exactly these bodies, one after another (after the session check)
seq_files() {
    local dir="$1" n=1 b; shift
    rm -rf "${dir:?}"; mkdir -p "${dir}"
    echo '{"loginName":"admin"}' > "${dir}/1.json"
    for b in "$@"; do n=$((n + 1)); printf '%s\n' "${b}" > "${dir}/${n}.json"; done
    SEQ_DIR="${dir}"
}
# opt_seq DIR BODY...: each GET answers {"result":[BODY]}, the last repeating
opt_seq() {
    local dir="$1" n=0 b; shift
    rm -rf "${dir:?}"; mkdir -p "${dir}"
    echo '{"loginName":"admin"}' > "${dir}/1.json"; n=1   # the first GET is the session check
    for b in "$@"; do n=$((n + 1)); printf '{"result":[%s]}\n' "${b}" > "${dir}/${n}.json"; done
    SEQ_DIR="${dir}"
}
# patch_run SCRIPT STATUSES: the HEAD answers 200 and the PATCHes the statuses, one each
patch_run() { local s="$1" st="$2"; shift 2; STUB_STATUS_HEAD=200 STUB_STATUS_PATCH_SEQ="${st}" urun "${s}" "$@"; }

ACCT='{"notes":null,"contact":{"email":"example_chg@example.com","phone":null},"user":{"failedAuthMaximum":3},"uid":"54321","bandwidthLimits":{"policy":"default","inboundLimit":null,"outboundLimit":null},"transfersWebServiceAllowed":false,"authByEmail":false,"disabled":false}'
ROUTE='{"description":"d","steps":[{"id":"s1","fileFilterExpression":"*.one","status":"ENABLED"},{"id":"s2","fileFilterExpression":"*.two","status":"ENABLED"}]}'
SEQ_DIR=""
start_state

echo "=== every script refuses a name that is not example_*, and extra parameters, before any call ==="
for s in 01.object_POST 02.object_GET 03.patch_string 04.patch_number 05.patch_boolean 06.patch_list 07.patch_null_and_object 08.patch_mistakes 09.put_whole_object 10.put_fragment 99.cleanup_DELETE 00.run_all; do
    urun "${s}.sh" real_account
    expect "${s}: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
    has "${s}: with the reason" "NAME is 'real_account': it must start with example_"
    has "${s}: and the usage" "Usage: ./${s}.sh [NAME]"
    urun "${s}.sh" example_a extra
    expect "${s}: two parameters is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
    has "${s}: and it says how many were given" "2 parameters were given, and at most 1 is taken: NAME."
done
urun 11.options_save_change_restore.sh "bad name"
expect "11: an option name with a space is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "11: with the usage" "Usage: ./11.options_save_change_restore.sh [OPTION] [VALUE]"
urun 11.options_save_change_restore.sh a b c
expect "11: three parameters is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== a step on an object that is not there says what to run first, and changes nothing ==="
for s in 03.patch_string 04.patch_number 05.patch_boolean 07.patch_null_and_object 08.patch_mistakes; do
    STUB_STATUS_HEAD=404 urun "${s}.sh"
    expect "${s}: no account is exit 1, one HEAD, no PATCH" "${RC}:$(ucalls)" "1:HEAD ${ACC} "
    has "${s}: and says to run 01 first" "Run 01.object_POST.sh first."
    STUB_STATUS_HEAD=500 urun "${s}.sh"
    expect "${s}: a HEAD that is not 200 or 404 is exit 1, no PATCH" "${RC}:$(calls | grep -c PATCH)" "1:0"
    has "${s}: and says it could not tell" "Could not tell whether the account of example_chg exists (HTTP 500). Nothing was changed."
done
for s in 06.patch_list 09.put_whole_object 10.put_fragment; do
    STUB_STATUS_HEAD=404 urun "${s}.sh"
    expect "${s}: no route is exit 1, one HEAD, nothing changed" "${RC}:$(ucalls)" "1:HEAD ${RT} "
    has "${s}: and says to run 01 first" "Run 01.object_POST.sh first."
done
rm -f "${UC}/state.local.route_id"
GET_BODY="${WORK}/noroute.json" urun 06.patch_list.sh
expect "06: with no saved route id it looks the route up by name, and finds none: exit 1, no HEAD, no PATCH" "${RC}:$(ucalls)" "1:GET ${BASE}/routes?name=example_chg_route&fields=id,name "
has "06: and says there is no route" "There is no route example_chg_route. Run 01.object_POST.sh first."
start_state

echo "=== 01 the objects are made ==="
rm -f "${UC}/state.local.route_id"
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 STUB_CURL_LOCATION_ID=rid9 urun 01.object_POST.sh
expect "01: HEAD the account, look the route up, POST the account, POST the route" "${RC}:$(ucalls)" \
  "0:HEAD ${ACC} GET ${BASE}/routes?name=example_chg_route&fields=id,name POST ${BASE}/accounts POST ${BASE}/routes "
expect "01: a user account with a home folder, an email, the same uid and gid, and a password" \
  "$(payload 1 | jq -c '[.name, .type, .homeFolder, .contact.email, (.uid == .gid), (.uid | tonumber >= 50000 and tonumber <= 59999), (.user.passwordCredentials.password | length > 8), .user.name]')" \
  '["example_chg","user","/home/example_chg","example_chg@example.com",true,true,true,"example_chg"]'
FIRST_UID=$(payload 1 | jq -r .uid)
expect "01: the route is a SIMPLE route named NAME_route with two EncodingConversion steps, *.one then *.two" \
  "$(payload 2 | jq -c '[.name, .type, .conditionType, (.steps | map(.type)), (.steps | map(.fileFilterExpression)), (.steps | map(.status))]')" \
  '["example_chg_route","SIMPLE","ALWAYS",["EncodingConversion","EncodingConversion"],["*.one","*.two"],["ENABLED","ENABLED"]]'
expect "01: each step has what the server asks for (the charsets, the filter type, what to do on failure)" \
  "$(payload 2 | jq -c '.steps[0] | [.inputCharset, .outputCharset, .fileFilterExpressionType, .actionOnStepFailure, .usePrecedingStepFiles]')" '["UTF-8","UTF-8","GLOB","PROCEED",false]'
expect "01: the POSTs carry accept, Referer, the content type and the csrfToken" "$(hdrs_of POST | grep -cE '^(Referer: |Content-Type: application/json|accept: \*/\*|csrfToken:)')" "4"
expect "01: the id from the Location header is kept in state.local.route_id" "$(cat "${UC}/state.local.route_id")" "rid9"
has "01: and said" "The route is rid9 (kept in state.local.route_id)."
rm -f "${UC}/state.local.route_id"
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 STUB_CURL_LOCATION_ID=rid9 urun 01.object_POST.sh example_chg
expect "01: the same name has the same user id every time" "$(payload 1 | jq -r .uid)" "${FIRST_UID}"
rm -f "${UC}/state.local.route_id"
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 STUB_CURL_LOCATION_ID=rid9 urun 01.object_POST.sh example_other
expect "01: another name has its own account, folder and route" "$(payload 1 | jq -c '[.name, .homeFolder, (.uid != "'"${FIRST_UID}"'")]'):$(payload 2 | jq -r .name)" '["example_other","/home/example_other",true]:example_other_route'
rm -f "${UC}/state.local.route_id"
STUB_STATUS_HEAD=200 urun 01.object_POST.sh
expect "01: an account that exists is not made again: exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
has "01: and it says so, and how to remove it" "The account example_chg already exists. Nothing was created. Remove it with 99.cleanup_DELETE.sh example_chg"
STUB_STATUS_HEAD=500 urun 01.object_POST.sh
expect "01: a HEAD that is not 200 or 404 is exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
has "01: and says it could not tell" "Could not tell whether the account example_chg exists (HTTP 500). Nothing was created."
GET_BODY="${WORK}/oneroute.json" STUB_STATUS_HEAD=404 urun 01.object_POST.sh
expect "01: a route that exists is not made again either: exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
has "01: and it says so" "The route example_chg_route already exists. Nothing was created."
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST=400 urun 01.object_POST.sh
expect "01: a refused account is exit 1 and the route is not made" "${RC}:$(calls | grep -c 'POST .*/routes')" "1:0"
has "01: and says the account was not made" "The account was not made."
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST_SEQ="201 400" STUB_CURL_LOCATION_ID=rid9 urun 01.object_POST.sh
expect "01: a refused route is exit 1, and no route id is kept" "${RC}:$([ -e "${UC}/state.local.route_id" ] && echo kept || echo none)" "1:none"
has "01: it says how to remove the account that was made" "The route was not made. The account example_chg was: remove it with 99.cleanup_DELETE.sh example_chg."
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 urun 01.object_POST.sh
expect "01: a route answered with no Location header is exit 1" "${RC}:$([ -e "${UC}/state.local.route_id" ] && echo kept || echo none)" "1:none"
has "01: and says the id is not known" "The server gave no Location header, so the id of the route is not known."
start_state

echo "=== 02 read first, keep a copy ==="
echo "${ACCT}" > "${WORK}/acct.json"
echo "${ROUTE}" > "${WORK}/route.json"
RULESF="${WORK}/rules02.tsv"; printf '/accounts/example_chg\t%s\n/routes/rid1\t%s\n' "${WORK}/acct.json" "${WORK}/route.json" > "${RULESF}"
STUB_STATUS_HEAD=200 STUB_STATUS_GET=200 RULES="${RULESF}" urun 02.object_GET.sh
expect "02: HEAD the account, HEAD the route, GET the account, GET the route" "${RC}:$(ucalls)" "0:HEAD ${ACC} HEAD ${RT} GET ${ACC} GET ${RT} "
expect "02: keeps a copy of each" "$(jq -c '.uid' "${UC}/state.local.account.json"):$(jq -c '.steps | length' "${UC}/state.local.route.json")" '"54321":2'
has "02: shows a number as a number" "user.failedAuthMaximum         number   3"
has "02: and the uid, which looks like one, as a string" "uid                            string   \"54321\""
has "02: a boolean" "transfersWebServiceAllowed     boolean  false"
has "02: a null as null" "notes                          null     null"
has "02: an object" "contact                        object   {\"email\":\"example_chg@example.com\",\"phone\":null}"
has "02: a list, with the count" "steps                          array    2 steps"
has "02: and each step by position, with its filter and id" "position 1: fileFilterExpression *.two, status ENABLED, id s2"
STUB_STATUS_HEAD=200 STUB_STATUS_GET=500 RULES="${RULESF}" urun 02.object_GET.sh
expect "02: an account that cannot be read is exit 1, and no copy is kept" "${RC}:$([ -e "${UC}/state.local.account.json" ] && echo kept || echo none)" "1:none"
has "02: and says so" "The account could not be read."
STUB_STATUS_HEAD=200 STUB_STATUS_GET_SEQ="200 500" RULES="${RULESF}" urun 02.object_GET.sh
rm -f "${UC}/state.local.account.json" "${UC}/state.local.route.json"

echo "=== 03 a string ==="
mk_seq "${WORK}/seq03" "${ACCT}" 0 '.notes="first note"' '.contact.email="changed@example.com"' '.contact.phone="+359 2 000 0000"' '.contact.phone=null' '.notes="5"' '.' '.notes=null'
BODY_OTHER="${WORK}/err.json" patch_run 03.patch_string.sh "204 204 204 204 204 400 204"
expect "03: HEAD, then seven cases of GET, PATCH, GET" "${RC}:$(ucalls)" "0:$(cases 7 "${ACC}")"
expect "03: the seven bodies: text in quotes, a number and a list to a text field, and the empty text" "$(bodies | tr '\n' ' ')" \
  '[{"op":"replace","path":"/notes","value":"first note"}] [{"op":"replace","path":"/contact/email","value":"changed@example.com"}] [{"op":"add","path":"/contact/phone","value":"+359 2 000 0000"}] [{"op":"remove","path":"/contact/phone"}] [{"op":"replace","path":"/notes","value":5}] [{"op":"replace","path":"/notes","value":["a"]}] [{"op":"replace","path":"/notes","value":""}] '
expect "03: the text is a JSON string and the number is a JSON number" "$(payload 1 | jq -c '.[0].value | type'):$(payload 5 | jq -c '.[0].value | type')" '"string":"number"'
expect "03: every PATCH carries accept, Referer, the content type and the csrfToken" "$(hdrs_of PATCH | grep -cE '^(Referer: |Content-Type: application/json|accept: application/json|csrfToken: tok123)')" "4"
has "03: shows the answer of each case" "  answer:  HTTP 204"
has "03: and the message of the refusal, indented" "           Incorrect JSON format"
has "03: a text that was a null shows before null" "  before:  null"
hasnt "03: and nothing is marked as not documented" "NOT AS DOCUMENTED"
expect "03: exit 0" "${RC}" "0"
mk_seq "${WORK}/seq03b" "${ACCT}" 0 '.' '.contact.email="changed@example.com"' '.contact.phone="+359 2 000 0000"' '.contact.phone=null' '.notes="5"' '.' '.notes=null'
patch_run 03.patch_string.sh "204 204 204 204 204 400 204"
expect "03: a change the server answered 204 and did not make is exit 1" "${RC}" "1"
has "03: and the line says what was expected and what came" 'NOT AS DOCUMENTED: this use case expects HTTP 204 and "first note". The server answered HTTP 204 and null.'
has "03: and the end says so" "At least one case did not come out as documented"
mk_seq "${WORK}/seq03c" "${ACCT}" 0 '.notes="first note"' '.contact.email="changed@example.com"' '.contact.phone="+359 2 000 0000"' '.contact.phone=null' '.notes="5"' '.' '.notes=null'
patch_run 03.patch_string.sh "204 204 204 204 204 204 204"
expect "03: a refusal that was not given (204 for the list) is exit 1 too" "${RC}" "1"
has "03: and names what was expected" "expects HTTP 400"

echo "=== 04 a number ==="
mk_seq "${WORK}/seq04" "${ACCT}" 1 '.user.failedAuthMaximum=5' '.user.failedAuthMaximum=7' '.' '.user.failedAuthMaximum=2' '.' '.user.failedAuthMaximum=3' \
  '.bandwidthLimits.policy="custom" | .bandwidthLimits.inboundLimit=512' '.bandwidthLimits.inboundLimit=null' '.bandwidthLimits.policy="default"' '.uid="60000"' '.uid="54321"'
patch_run 04.patch_number.sh "204 204 400 204 400 204 204 204 204 204 204"
expect "04: HEAD, a read of the uid, then eleven cases" "${RC}:$(ucalls)" "0:HEAD ${ACC} GET ${ACC} $(cases 11 "${ACC}" | sed "s|^HEAD ${ACC} ||")"
expect "04: the bodies: a number with no quotes, then in quotes, a text, a decimal, a negative, a remove" "$(bodies | head -6 | tr '\n' ' ')" \
  '[{"op":"replace","path":"/user/failedAuthMaximum","value":5}] [{"op":"replace","path":"/user/failedAuthMaximum","value":"7"}] [{"op":"replace","path":"/user/failedAuthMaximum","value":"abc"}] [{"op":"replace","path":"/user/failedAuthMaximum","value":2.5}] [{"op":"replace","path":"/user/failedAuthMaximum","value":-1}] [{"op":"remove","path":"/user/failedAuthMaximum"}] '
expect "04: a limit needs the policy: two operations in one patch, the policy first" "$(payload 7 | jq -c '[.[] | [.op, .path, .value]]')" '[["replace","/bandwidthLimits/policy","custom"],["replace","/bandwidthLimits/inboundLimit",512]]'
expect "04: the limit is written as a number, the second case's value as text" "$(payload 1 | jq -c '.[0].value | type'):$(payload 2 | jq -c '.[0].value | type'):$(payload 7 | jq -c '.[1].value | type')" '"number":"string":"number"'
expect "04: a number sent to the uid, then the old uid back as TEXT (the uid read before the cases)" "$(payload 10 | jq -c '.[0].value | type'):$(payload 11 | jq -c '.[0]')" '"number":{"op":"replace","path":"/uid","value":"54321"}'
expect "04: the policy is put back" "$(payload 9 | jq -c '.[0]')" '{"op":"replace","path":"/bandwidthLimits/policy","value":"default"}'
has "04: says what a decimal does" "the part after the point is dropped, with no warning"
hasnt "04: all as documented" "NOT AS DOCUMENTED"
expect "04: exit 0" "${RC}" "0"
mk_seq "${WORK}/seq04b" "${ACCT}" 1 '.user.failedAuthMaximum=5' '.user.failedAuthMaximum=7' '.' '.user.failedAuthMaximum=3' '.' '.user.failedAuthMaximum=3' \
  '.bandwidthLimits.policy="custom" | .bandwidthLimits.inboundLimit=512' '.bandwidthLimits.inboundLimit=null' '.bandwidthLimits.policy="default"' '.uid="60000"' '.uid="54321"'
patch_run 04.patch_number.sh "204 204 400 204 400 204 204 204 204 204 204"
expect "04: a decimal that the server keeps whole (3, not 2) is exit 1: the server is another release" "${RC}" "1"

echo "=== 05 a boolean ==="
mk_seq "${WORK}/seq05" "${ACCT}" 0 '.transfersWebServiceAllowed=true' '.transfersWebServiceAllowed=false' '.' '.transfersWebServiceAllowed=true' '.transfersWebServiceAllowed=false' '.' '.authByEmail=true' '.authByEmail=false'
patch_run 05.patch_boolean.sh "204 204 400 204 204 400 204 204"
expect "05: HEAD, then eight cases" "${RC}:$(ucalls)" "0:$(cases 8 "${ACC}")"
expect "05: the bodies: true, \"false\", \"yes\", 1, remove, null, true, false" "$(bodies | jq -c '.[0] | [.op, .path, .value]' | tr '\n' ' ')" \
  '["replace","/transfersWebServiceAllowed",true] ["replace","/transfersWebServiceAllowed","false"] ["replace","/transfersWebServiceAllowed","yes"] ["replace","/transfersWebServiceAllowed",1] ["remove","/transfersWebServiceAllowed",null] ["replace","/disabled",null] ["replace","/authByEmail",true] ["replace","/authByEmail",false] '
expect "05: a real boolean is not in quotes" "$(payload 1 | jq -c '.[0].value | type'):$(payload 2 | jq -c '.[0].value | type'):$(payload 7 | jq -c '.[0].value | type')" '"boolean":"string":"boolean"'
hasnt "05: all as documented" "NOT AS DOCUMENTED"
expect "05: exit 0" "${RC}" "0"
patch_run 05.patch_boolean.sh "204 204 204 204 204 400 204 204"
expect "05: a word that the server accepts as a boolean (204 for \"yes\") is exit 1" "${RC}" "1"

echo "=== 06 a list ==="
mk_seq "${WORK}/seq06" "${ROUTE}" 2 \
  '.steps += [{"id":"s3","fileFilterExpression":"*.three"}]' \
  '.steps = [{"id":"s0","fileFilterExpression":"*.zero"}] + .steps' \
  '.steps[1].fileFilterExpression="*.uno"' \
  '.steps[0].fileFilterExpression="*.first"' \
  'del(.steps[0])' READ 'del(.steps[1])' '.' '.' '.' '.' '.steps=[]' \
  '.steps=[{"fileFilterExpression":"*.one"},{"fileFilterExpression":"*.two"}]'
patch_run 06.patch_list.sh "204 204 204 204 204 204 400 400 400 204 204 204"
expect "06: HEAD, the first step's id, the list, twelve cases and one read of the position between" "${RC}:$(ucalls | sed "s|HEAD ${RT} ||" | wc -w | tr -d ' ')" "0:$(( 2 * 2 + 12 * 6 + 2 ))"
expect "06: the first operation of each body: the end is -, a position is a number, a path never has an id except the one refused" "$(firsts)" \
  'add /steps/-;add /steps/0;replace /steps/1/fileFilterExpression;replace /steps/0;remove /steps/0;remove /steps/1;add /steps/9;replace /steps/s1/status;replace /steps;remove /steps/-;replace /steps;replace /steps;'
expect "06: the position of the step to remove is found in what was read (*.two is at 1)" "$(payload 6 | jq -c .)" '[{"op":"remove","path":"/steps/1"}]'
expect "06: the id of the first step (read first) is what the refused path carries" "$(payload 8 | jq -r '.[0].path')" "/steps/s1/status"
expect "06: an added step is a whole step: type, status, filter, charsets" "$(payload 1 | jq -c '.[0].value | [.type, .status, .fileFilterExpression, .inputCharset, .outputCharset]')" '["EncodingConversion","ENABLED","*.three","UTF-8","UTF-8"]'
expect "06: the whole list is replaced with an empty one, then with two steps" "$(payload 11 | jq -c '.[0].value'):$(payload 12 | jq -c '.[0].value | map(.fileFilterExpression)')" '[]:["*.one","*.two"]'
has "06: says the position it found" "The step with the filter *.two is at position 1"
hasnt "06: all as documented" "NOT AS DOCUMENTED"
expect "06: exit 0" "${RC}" "0"
patch_run 06.patch_list.sh "204 204 204 204 204 204 204 400 400 204 204 204"
expect "06: a position past the end that the server accepts (204) is exit 1" "${RC}" "1"

echo "=== 07 a null and an object ==="
mk_seq "${WORK}/seq07" "${ACCT}" 0 '.contact.email=null' '.' '.bandwidthLimits={"policy":"custom","inboundLimit":100,"outboundLimit":200}' '.bandwidthLimits.outboundLimit=null' \
  '.bandwidthLimits.outboundLimit=300' '.contact={"email":"a@example.com","phone":"123"}' '.contact={"email":null,"phone":null}' '.'
patch_run 07.patch_null_and_object.sh "204 400 204 204 204 204 204 400"
expect "07: HEAD, then eight cases" "${RC}:$(ucalls)" "0:$(cases 8 "${ACC}")"
expect "07: the bodies: null, a whole object, a fragment of one, a field inside it, an object, remove, and null for an object" "$(bodies | jq -c '.[0] | [.op, .path, .value]' | tr '\n' ' ')" \
  '["replace","/contact/email",null] ["replace","/disabled",null] ["replace","/bandwidthLimits",{"policy":"custom","inboundLimit":100,"outboundLimit":200}] ["replace","/bandwidthLimits",{"policy":"custom","inboundLimit":100}] ["replace","/bandwidthLimits/outboundLimit",300] ["replace","/contact",{"email":"a@example.com","phone":"123"}] ["remove","/contact",null] ["replace","/contact",null] '
hasnt "07: all as documented" "NOT AS DOCUMENTED"
expect "07: exit 0" "${RC}" "0"
patch_run 07.patch_null_and_object.sh "204 400 204 204 204 204 204 204"
expect "07: null for an object that the server accepts is exit 1" "${RC}" "1"

echo "=== 08 what goes wrong ==="
mk_seq "${WORK}/seq08" "${ACCT}" 1 '.' '.' '.' '.' '.' '.' '.'
patch_run 08.patch_mistakes.sh "400 204 400 400 400 415 415"
expect "08: HEAD, the notes read once, then seven cases" "${RC}:$(ucalls)" "0:HEAD ${ACC} GET ${ACC} $(cases 7 "${ACC}" | sed "s|^HEAD ${ACC} ||")"
expect "08: all or nothing is two operations, the second wrong; the typo is in the path of an add" "$(payload 1 | jq -c '[.[] | .path]'):$(payload 2 | jq -r '.[0] | .op + " " + .path')" '["/notes","/nosuchfield"]:add /contact/phon'
expect "08: a body that is one operation is not a list" "$(payload 4 | jq -c 'type'):$(payload 1 | jq -c 'type')" '"object":"array"'
expect "08: an operation that does not exist is swap" "$(payload 5 | jq -r '.[0].op')" "swap"
expect "08: one call has no content type (the header is removed), one has text/plain, the others have application/json" \
  "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type:$'):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: text/plain$'):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: application/json$')" "1:1:5"
hasnt "08: all as documented" "NOT AS DOCUMENTED"
expect "08: exit 0" "${RC}" "0"
patch_run 08.patch_mistakes.sh "400 204 400 400 400 204 415"
expect "08: a request with no Content-Type that the server accepts is exit 1" "${RC}" "1"
mk_seq "${WORK}/seq08b" "${ACCT}" 1 '.notes="first"' '.' '.' '.' '.' '.' '.'
patch_run 08.patch_mistakes.sh "400 204 400 400 400 415 415"
expect "08: a patch that was not all or nothing (the first operation applied) is exit 1" "${RC}" "1"
has "08: and shows the value that changed" 'The server answered HTTP 400 and "first".'

echo "=== 09 PUT the whole object ==="
ROUTE_FULL=$(echo "${ROUTE}" | jq -c '.metadata = {"links":{"route":"x"}} | .id = "rid1"')
CH1=$(echo "${ROUTE_FULL}" | jq -c '.description="changed by a PUT of the whole object"')
CH2=$(echo "${ROUTE_FULL}" | jq -c '.description="no metadata"')
seq_files "${WORK}/seq09" "${ROUTE_FULL}" "${CH1}" "${CH2}"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="204 204 400" BODY_OTHER="${WORK}/err.json" urun 09.put_whole_object.sh
expect "09: HEAD, the read, a PUT, the read again, a PUT, a PUT, the read" "${RC}:$(ucalls)" "0:HEAD ${RT} GET ${RT} PUT ${RT} GET ${RT} PUT ${RT} PUT ${RT} GET ${RT} "
expect "09: the first PUT is the object as read, with one field changed, metadata and ids included" \
  "$(payload 1 | jq -S -c .)" "$(echo "${CH1}" | jq -S -c .)"
expect "09: the second has no metadata" "$(payload 2 | jq -c '[has("metadata"), has("id"), (.steps | map(has("id")))]')" '[false,true,[true,true]]'
expect "09: the third has no id of the route, and the steps keep theirs" "$(payload 3 | jq -c '[has("metadata"), has("id"), (.steps | map(has("id")))]')" '[false,false,[true,true]]'
expect "09: the PUTs carry accept, Referer, the content type and the csrfToken" "$(hdrs_of PUT | grep -cE '^(Referer: |Content-Type: application/json|accept: application/json|csrfToken: tok123)')" "4"
has "09: says that only the description differs" "Compared with the copy: only the description differs."
has "09: and what the refused PUT said" "           Incorrect JSON format"
hasnt "09: all as documented" "NOT AS DOCUMENTED"
expect "09: exit 0" "${RC}" "0"
seq_files "${WORK}/seq09b" "${ROUTE_FULL}" "$(echo "${CH1}" | jq -c '.steps[0].status="DISABLED"')" "${CH2}"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="204 204 400" urun 09.put_whole_object.sh
expect "09: another field that differs after the PUT is exit 1" "${RC}" "1"
has "09: and the line says so" "NOT AS DOCUMENTED: something besides the description differs from the copy that was read."
seq_files "${WORK}/seq09c" "${ROUTE_FULL}" "${CH1}" "${CH2}"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="204 204 204" urun 09.put_whole_object.sh
expect "09: a PUT without the route id that the server accepts is exit 1" "${RC}" "1"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="400 204 400" urun 09.put_whole_object.sh
expect "09: a PUT of the object as read that is refused is exit 1" "${RC}" "1"
has "09: and says what was expected" "expects HTTP 204. The server answered HTTP 400."

echo "=== 10 PUT a fragment, and the way back ==="
SAVED_R='{"id":"rid1","name":"example_chg_route","type":"SIMPLE","conditionType":"ALWAYS","description":"orig","metadata":{"links":{}},"steps":[{"id":"s1","precedingStep":null,"metadata":{"links":{}},"type":"EncodingConversion","fileFilterExpression":"*.one"},{"id":"s2","precedingStep":"s1","metadata":{"links":{}},"type":"EncodingConversion","fileFilterExpression":"*.two"}]}'
FRAG=$(echo "${SAVED_R}" | jq -c '.description="a fragment" | .steps=[]')
REST1=$(echo "${SAVED_R}" | jq -c '.description="a fragment" | .steps=[{"fileFilterExpression":"*.one"},{"fileFilterExpression":"*.two"}]')
REST2=$(echo "${SAVED_R}" | jq -c '.steps=[{"fileFilterExpression":"*.one"},{"fileFilterExpression":"*.two"}]')
seq_files "${WORK}/seq10" "${SAVED_R}" "${FRAG}" "${FRAG}" "${FRAG}" "${FRAG}" "${REST1}" "${REST1}" "${REST2}"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="204 404" STUB_STATUS_PATCH_SEQ="204 204" urun 10.put_fragment.sh
expect "10: HEAD, the read, the PUT of the fragment, two reads, the PUT of the copy, a read, then two cases" "${RC}:$(ucalls)" \
  "0:HEAD ${RT} GET ${RT} PUT ${RT} GET ${RT} GET ${RT} PUT ${RT} GET ${RT} GET ${RT} PATCH ${RT} GET ${RT} GET ${RT} PATCH ${RT} GET ${RT} "
expect "10: the fragment has exactly four fields" "$(payload 1 | jq -c 'keys')" '["conditionType","description","name","type"]'
expect "10: the copy that is PUT back is what was read, without metadata, with the old ids" "$(payload 2 | jq -S -c .)" "$(echo "${SAVED_R}" | jq -S -c 'del(.metadata)')"
expect "10: the way back is a PATCH that replaces the list, with the steps minus id, precedingStep and metadata" "$(payload 3 | jq -c '[.[0].op, .[0].path, (.[0].value | map(keys))]')" \
  '["replace","/steps",[["fileFilterExpression","type"],["fileFilterExpression","type"]]]'
expect "10: then the description" "$(payload 4 | jq -c .)" '[{"op":"replace","path":"/description","value":"orig"}]'
has "10: says the steps are gone" "THE STEPS ARE GONE. The server answered 204 and said nothing about it."
has "10: and why the copy is refused" "(the ids in the copy name steps that no longer exist)"
hasnt "10: all as documented" "NOT AS DOCUMENTED"
expect "10: exit 0" "${RC}" "0"
STILL=$(echo "${SAVED_R}" | jq -c '.description="a fragment"')
seq_files "${WORK}/seq10b" "${SAVED_R}" "${STILL}" "${STILL}" "${STILL}" "${STILL}" "${REST1}" "${REST1}" "${REST2}"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT_SEQ="204 404" STUB_STATUS_PATCH_SEQ="204 204" urun 10.put_fragment.sh
expect "10: a fragment that does not remove the steps is exit 1" "${RC}" "1"
has "10: and the line says so" "NOT AS DOCUMENTED: the steps are still there."

echo "=== 11 a server option: save, change, put back ==="
OPTSAVED="{\"name\":\"${OPT}\",\"values\":[\"100\"],\"defaultValues\":[\"100\"],\"specified\":true,\"readOnly\":false}"
OPT77=$(echo "${OPTSAVED}" | jq -c '.values=["77"]')
OPTURL="${BASE}/configurations/options?name=${OPT}"
PUTURL="${BASE}/configurations/options"
rm -f "${UC}/state.local.option.json"
opt_seq "${WORK}/seq11" "${OPTSAVED}" "${OPT77}" "${OPT77}" "${OPT77}" "${OPT77}" "${OPTSAVED}"
STUB_STATUS_PUT_SEQ="204 400 400 404 204" urun 11.options_save_change_restore.sh
expect "11: reads the option, PUTs it, reads, three wrong PUTs each with a read, the PUT back, a read" "${RC}:$(ucalls)" \
  "0:GET ${OPTURL} PUT ${PUTURL} GET ${OPTURL} PUT ${PUTURL} GET ${OPTURL} PUT ${PUTURL} GET ${OPTURL} PUT ${PUTURL} GET ${OPTURL} PUT ${PUTURL} GET ${OPTURL} "
expect "11: the change is a list of one object with name and values (a list of text)" "$(payload 1 | jq -c .)" "[{\"name\":\"${OPT}\",\"values\":[\"77\"]}]"
expect "11: the wrong shapes: value for values, one object not a list, an option that does not exist" "$(payload 2 | jq -c '.[0] | keys'):$(payload 3 | jq -c 'type'):$(payload 4 | jq -r '.[0].name')" '["name","value"]:"object":No.Such.Option'
expect "11: the option is put back with the values that were saved" "$(payload 5 | jq -c .)" "[{\"name\":\"${OPT}\",\"values\":[\"100\"]}]"
expect "11: the PUTs carry accept, Referer, the content type and the csrfToken" "$(hdrs_of PUT | grep -cE '^(Referer: |Content-Type: application/json|accept: application/json|csrfToken: tok123)')" "4"
has "11: says what it saved" "Saved: {\"name\":\"${OPT}\",\"values\":[\"100\"],\"defaultValues\":[\"100\"],\"specified\":true,\"readOnly\":false}"
has "11: and that the option is as it was" "is as it was: the answer now is the same, field for field, as the copy that was saved."
expect "11: the saved copy is gone when it is back" "$([ -e "${UC}/state.local.option.json" ] && echo kept || echo gone)" "gone"
hasnt "11: all as documented" "NOT AS DOCUMENTED"
OPT5=$(echo "${OPTSAVED}" | jq -c '.values=["5"]')
opt_seq "${WORK}/seq11b" "${OPTSAVED}" "${OPT5}" "${OPT5}" "${OPT5}" "${OPT5}" "${OPTSAVED}"
STUB_STATUS_PUT_SEQ="204 400 400 404 204" urun 11.options_save_change_restore.sh "${OPT}" 5
expect "11: VALUE is what is set" "$(payload 1 | jq -c '.[0].values')" '["5"]'
opt_seq "${WORK}/seq11c" "${OPTSAVED}" "${OPT77}" "${OPT77}" "${OPT77}" "${OPT77}" "$(echo "${OPTSAVED}" | jq -c '.specified=false')"
STUB_STATUS_PUT_SEQ="204 400 400 404 204" urun 11.options_save_change_restore.sh
expect "11: the values are back but another field differs: exit 0" "${RC}" "0"
has "11: and it names the field" "These fields differ from the saved copy: specified"
opt_seq "${WORK}/seq11d" "${OPTSAVED}" "${OPT77}" "${OPT77}" "${OPT77}" "${OPT77}" "${OPT77}"
STUB_STATUS_PUT_SEQ="204 400 400 404 204" urun 11.options_save_change_restore.sh
expect "11: an option that is NOT back is exit 1, and the saved copy stays" "${RC}:$([ -s "${UC}/state.local.option.json" ] && echo kept || echo gone)" "1:kept"
has "11: and says what to do" "The option is NOT back as it was. The saved copy stays in state.local.option.json: run 99.cleanup_DELETE.sh to try again, or set ${OPT} by hand."
urun 11.options_save_change_restore.sh
expect "11: with a saved copy there, it refuses to start: exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
has "11: and says to run 99 first" "There is a saved copy of an option from an earlier run (state.local.option.json). Run 99.cleanup_DELETE.sh first: it puts the option back."
rm -f "${UC}/state.local.option.json"
opt_seq "${WORK}/seq11e" "${OPTSAVED}" "${OPTSAVED}" "${OPTSAVED}"
STUB_STATUS_PUT_SEQ="204 204" urun 11.options_save_change_restore.sh
expect "11: a change that did not take is exit 1, the wrong shapes are not tried, and the option is put back" "${RC}:$(calls | grep -c PUT)" "1:2"
has "11: and it says so" "The change did not take. Putting the option back."
rm -f "${UC}/state.local.option.json"
opt_seq "${WORK}/seq11f" "$(echo "${OPTSAVED}" | jq -c '.readOnly=true')"
STUB_STATUS_PUT_SEQ="204" urun 11.options_save_change_restore.sh
expect "11: a read only option is exit 1, no PUT, no saved copy" "${RC}:$(calls | grep -c PUT):$([ -e "${UC}/state.local.option.json" ] && echo kept || echo none)" "1:0:none"
has "11: and says so" "The option ${OPT} is read only. Nothing was changed."
SEQ_DIR="" GET_BODY="${WORK}/noroute.json" urun 11.options_save_change_restore.sh
expect "11: an option that does not exist is exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
has "11: and says so" "There is no option ${OPT} on this server. Nothing was changed."
opt_seq "${WORK}/seq11g" "${OPTSAVED}"
urun 11.options_save_change_restore.sh "${OPT}" 100
expect "11: a VALUE the option already has is exit 1, no PUT, nothing saved" "${RC}:$(calls | grep -c PUT):$([ -e "${UC}/state.local.option.json" ] && echo kept || echo none)" "1:0:none"
has "11: and says to give another" "already has the value 100: give a VALUE that differs"
SEQ_DIR=""

echo "=== 99 the cleanup, twice ==="
start_state
echo "${OPTSAVED}" > "${UC}/state.local.option.json"; echo '{}' > "${UC}/state.local.account.json"; echo '{}' > "${UC}/state.local.route.json"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT=204 STUB_STATUS_DELETE=204 urun 99.cleanup_DELETE.sh
expect "99: puts the option back, deletes the route, deletes the account, ends the session" "${RC}:$(ucalls)" \
  "0:PUT ${PUTURL} HEAD ${RT} DELETE ${RT} HEAD ${ACC} DELETE ${ACC} DELETE ${BASE}/myself "
expect "99: the option goes back with the values that were saved" "$(payload 1 | jq -c .)" "[{\"name\":\"${OPT}\",\"values\":[\"100\"]}]"
has "99: says so" "The option ${OPT} was put back as saved: [\"100\"]."
has "99: and the route" "The route example_chg_route was deleted."
has "99: and the account" "The account example_chg was deleted."
expect "99: the state files and the jar are gone" "$(ls "${UC}" | grep -cE '^(state\.local\.(option\.json|route_id|account\.json|route\.json|csrf)|session\.cookie\.jar)')" "0"
STUB_STATUS_HEAD=404 STUB_STATUS_GET=200 GET_BODY="${WORK}/noroute.json" run 99.cleanup_DELETE.sh
expect "99: a second run: the route is looked up by name, nothing is found, nothing is deleted, exit 0" "${RC}:$(calls | grep -c DELETE):$(calls | grep -c PUT)" "0:0:0"
has "99: it says there is no route" "There is no route example_chg_route: nothing to delete."
has "99: and no account" "There is no account example_chg: nothing to delete."
has "99: and that it cleaned up" "Cleaned up."
start_state
echo "${OPTSAVED}" > "${UC}/state.local.option.json"
STUB_STATUS_HEAD=200 STUB_STATUS_PUT=400 STUB_STATUS_DELETE=204 urun 99.cleanup_DELETE.sh
expect "99: an option that cannot be put back is exit 1, the copy stays, and the objects are still deleted" "${RC}:$([ -s "${UC}/state.local.option.json" ] && echo kept || echo gone):$(calls | grep -c DELETE)" "1:kept:3"
has "99: it says what to set by hand" "The option ${OPT} could not be put back (HTTP 400). The copy stays in state.local.option.json: set it by hand to [\"100\"]."
start_state
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=403 urun 99.cleanup_DELETE.sh
expect "99: a route that cannot be deleted is exit 1, and the account is still tried" "${RC}:$(calls | grep -c 'DELETE .*accounts')" "1:1"
has "99: names the route and the code" "The route example_chg_route could not be deleted (HTTP 403): delete it by hand."
has "99: and the account" "The account example_chg could not be deleted (HTTP 403): delete it by hand."

echo "=== 00 run_all stops at the first failing step, and still cleans up ==="
clear_state
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD=200 run 00.run_all.sh example_chg_x
has "00: a step that fails stops it, by name (01 finds the account already there)" "01.object_POST failed."
has "00: and the cleanup still runs" "=== 99.cleanup_DELETE ==="
expect "00: exit 1, and no step after 01 ran" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== 02')" "1:0"
clear_state
GET_BODY="${WORK}/noroute.json" STUB_STATUS_HEAD_SEQ="404 200 200 200 200 200" STUB_STATUS_GET=200 STUB_STATUS_POST=201 STUB_CURL_LOCATION_ID=rid9 urun 00.run_all.sh example_chg_x
has "00: 01 and 02 ran" "=== 02.object_GET ==="
has "00: 03 ran and failed (the server did not change the notes)" "03.patch_string failed."
expect "00: nothing after 03 ran, the cleanup did, exit 1" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== 04'):$(printf '%s\n' "${OUT}" | grep -c '^=== 99')" "1:0:1"
run 00.run_all.sh real_account
expect "00: a name that does not start with example_ stops it at once: exit 2, nothing sent, no cleanup" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c '99.cleanup')" "2:0:0"
clear_state

echo "=== the scripts say where they were copied from ==="
for s in "${UC_ROOT}/05-changing-an-object"/[0-9][0-9].*.sh; do
    n="$(basename "${s}")"
    case "${n}" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/API 2.0\/bash\/[^ ,]*).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_05: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_05: PASS"
