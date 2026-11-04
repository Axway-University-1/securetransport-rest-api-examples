#!/bin/bash
# ==============================================================================
# Run Admin/UseCases/09-resubmit-transfers against a stub curl, and check the calls each script makes: the method, the URL and the query it builds (account, resubmitted=false, the time window,
# limit; for 1.4 accountOrLogin on /api/v1.4), the body of a POST, the credentials (a session for 2.0, Basic for 1.4 and for the uploads), the headers, what it prints, and its exit code.
#
# 01 two accounts with the fixed user ids and one password (kept private), one that exists already, a refusal; 02 the six uploads on the End User port with the password, the window file, the
# wait for the log, an upload that is refused, no answer from the End User port, a log that never shows them; 2.0/01 the list and the decoded id; 2.0/02 one POST for each transfer with the
# csrfToken, a refused one that does not stop the others, nothing to resubmit; 2.0/03 the counts and the copies that do not come; 1.4/01 the preview with the criteria of 02; 1.4/02 the one
# call, ACCOUNT required, never without a criterion, a 200 that holds an ERROR entry is exit 1, a 400, an answer that is not a list; 1.4/03; 99 the exact names, 404 as not there, twice; 00
# failing fast and still cleaning up; the README against the folder.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_09"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/09-resubmit-transfers" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
BASE14="https://st.example.com:8444/api/v1.4"
EU="https://st.example.com:8443/api/v2.0"
UC="${WORK}/tree/UseCases/09-resubmit-transfers"
README_FILE="${UC_ROOT}/09-resubmit-transfers/README.md"
rm -rf "${UC}"/state.local.* "${UC}/session.cookie.jar"
WINDOW="Wed, 04 Nov 2026 09:15:19 +0200"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
rules() {
    local out="${WORK}/rules_${RANDOM}${RANDOM}.tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# t20 TOTAL FLAGGED: a 2.0 transfer list of TOTAL entries, the first FLAGGED of them flagged resubmitted (ids ID1, ID2, ...)
t20() {
    jq -cn --argjson total "$1" --argjson flagged "$2" '{resultSet: {returnCount: $total, totalCount: $total},
        result: [range(1; $total + 1) as $i | {id: {mTransferStatusId: "t\($i)", mTransferStartTime: $i, urlrepresentation: "SWQgW21U\($i)"}, filename: "report_\($i).txt", status: "Processed", resubmitted: ($i <= $flagged)}]}'
}
# t14 TOTAL FLAGGED: the same list as the API 1.4 answers it
t14() {
    jq -cn --argjson total "$1" --argjson flagged "$2" '{transferEntries: [range(1; $total + 1) as $i | {transferEntry: {filename: "report_\($i).txt", status: "Processed", direction: "Incoming", resubmitted: ($i <= $flagged)}}]}'
}
reset_counters() { rm -f "${WORK}"/ctr.*; }

# run SCRIPT [PARAMS]: with a session jar in place. RULES, GET_BODY, POST_BODY and the *_STATUS variables set the answers.
run() {
    local rel="$1"; shift
    reset_counters
    touch "${UC}/session.cookie.jar"
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_COUNTER="${WORK}/ctr" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_STATUS_GET="${GET_STATUS:-200}" STUB_STATUS_POST="${POST_STATUS:-201}" STUB_STATUS_POST_SEQ="${POST_SEQ:-}" STUB_STATUS_HEAD="${HEAD_STATUS:-404}" \
          STUB_STATUS_DELETE="${DELETE_STATUS:-204}" STUB_CURL_PRINT_CODE=1 ST_ENDUSER_PORT=8443 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }      # without the check of the session that comes first (GET /myself)
ncalls() { calls | wc -l | tr -d ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
PW="Ex1!abc123"

echo "=== 01 the accounts ==="
run 01.accounts_POST.sh
expect "01: exit 0, and two POSTs to /accounts after the HEAD of each" "${RC}:$(ucalls | grep -c '^HEAD'):$(ucalls | grep -c "^POST ${BASE}/accounts$")" "0:2:2"
expect "01: the first is the HEAD of example_rsb_a, then example_rsb_b" "$(ucalls | grep '^HEAD' | sed "s#HEAD ${BASE}/##" | tr '\n' ' ')" "accounts/example_rsb_a accounts/example_rsb_b "
expect "01: the body of the first account: a user, its own home, its fixed ids, the user and a password" \
    "$(payload 1 | jq -c '[.name, .type, .homeFolder, .uid, .gid, .user.name, (.user.passwordCredentials.password | length > 8)]')" '["example_rsb_a","user","/home/example_rsb_a","58301","58301","example_rsb_a",true]'
expect "01: and of the second, with its own ids" "$(payload 2 | jq -c '[.name, .homeFolder, .uid]')" '["example_rsb_b","/home/example_rsb_b","58302"]'
expect "01: one password for both" "$(payload 1 | jq -r .user.passwordCredentials.password)" "$(payload 2 | jq -r .user.passwordCredentials.password)"
expect "01: the password file holds it, and only its owner can read it" "$(cat "${UC}/state.local.password"):$(file_mode "${UC}/state.local.password")" "$(payload 1 | jq -r .user.passwordCredentials.password):600"
expect "01: the POSTs carry the csrfToken and the content type" "$(printf '%s\n' "${OUT}" | grep -cE '^HEADER: (csrfToken|Content-Type: application/json)')" "$(( $(printf '%s\n' "${OUT}" | grep -c '^METHOD: POST') * 2 ))"
rm -f "${UC}/state.local.password"
HEAD_STATUS=200 run 01.accounts_POST.sh
expect "01: an account that is there is exit 1, and nothing is created" "${RC}:$(ucalls | grep -c '^POST'):$(test -e "${UC}/state.local.password" && echo file || echo none)" "1:0:none"
has "01: it names the account and the cleanup" "example_rsb_a exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."
HEAD_STATUS=500 run 01.accounts_POST.sh
expect "01: an answer to the HEAD that is neither 200 nor 404 is exit 1, nothing created" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
POST_STATUS=400 POST_BODY="$(body e1 '{"validationErrors":["name is taken"]}')" run 01.accounts_POST.sh
expect "01: a POST that is refused is exit 1, the second account is not tried, and no password is kept" "${RC}:$(ucalls | grep -c '^POST'):$(test -e "${UC}/state.local.password" && echo file || echo none)" "1:1:none"
has "01: with the reason" "name is taken"
run 01.accounts_POST.sh now
expect "01: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm -f "${UC}/state.local.password"

echo "=== 02 the uploads ==="
printf '%s' "${PW}" > "${UC}/state.local.password"
LOG3="$(body l3 "$(t20 3 0)")"
RULES="$(rules 'logs/transfers' "${LOG3}")" run 02.uploads_POST.sh
expect "02: exit 0, six uploads (three each), POST /files on the End User port" "${RC}:$(ucalls | grep -c "^POST ${EU}/files$")" "0:6"
expect "02: as the account, with its password (Basic authentication)" "$(printf '%s\n' "${OUT}" | grep '^BASIC_AUTH:' | sort -u | tr '\n' ' ')" "BASIC_AUTH: example_rsb_a:${PW} BASIC_AUTH: example_rsb_b:${PW} "
expect "02: the files are report_1.txt to report_3.txt, for each account" "$(printf '%s\n' "${OUT}" | sed -n 's/^FORM: file=@[^;]*;filename=//p' | sort | uniq -c | awk '{printf "%s %s ", $1, $2}')" "2 report_1.txt 2 report_2.txt 2 report_3.txt "
expect "02: the time window is kept, in RFC 2822" "$(grep -cE '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$' "${UC}/state.local.window")" "1"
expect "02: the log is read for each account, after the window, with the status" "$(ucalls | grep -c 'logs/transfers?account=example_rsb_a&startTimeAfter=.*&limit=100&fields=status')" "1"
has "02: it says what the log shows" "The log shows, as Processed: example_rsb_a=3 example_rsb_b=3."
RULES="$(rules 'logs/transfers' "$(body l1 "$(t20 1 0)")")" run 02.uploads_POST.sh
expect "02: a log that never shows three each is exit 1 after 60 rounds" "${RC}:$(ucalls | grep -c 'logs/transfers?account=example_rsb_a')" "1:60"
has "02: it says what it saw and what it expected" "After 60 seconds the log shows, as Processed: example_rsb_a=1 example_rsb_b=1. Expected 3 for each."
RULES="$(rules 'logs/transfers' "$(body lp "$(t20 3 0 | jq -c '.result |= map(.status = "In Progress")')")")" run 02.uploads_POST.sh
expect "02: three transfers that are still In Progress are not enough: exit 1 after 60 rounds" "${RC}:$(ucalls | grep -c 'logs/transfers?account=example_rsb_a')" "1:60"
has "02: it says it saw none as Processed" "the log shows, as Processed: example_rsb_a=0 example_rsb_b=0."
RULES="$(rules 'logs/transfers' "${LOG3}")" POST_STATUS=403 run 02.uploads_POST.sh
expect "02: an upload that is refused is exit 1, and the next is not tried" "${RC}:$(ucalls | grep -c '^POST')" "1:1"
has "02: with its account, file and code" "example_rsb_a uploads report_1.txt: HTTP 403"
RULES="$(rules 'logs/transfers' "${LOG3}")" POST_STATUS=000 run 02.uploads_POST.sh
expect "02: no answer is exit 1 and names the End User port" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'The End User API has its own port: set ST_ENDUSER_PORT')" "1:1"
RULES="$(rules 'logs/transfers' "$(body le '{"message":"nope"}')")" GET_STATUS=500 run 02.uploads_POST.sh
expect "02: a log that is refused is exit 1 with the code" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'The transfer log of example_rsb_a: HTTP 500')" "1:1"
rm -f "${UC}/state.local.password"
run 02.uploads_POST.sh
expect "02: no password file is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
has "02: and it names step 01" "run 01.accounts_POST.sh first."
printf 'x' > "${UC}/state.local.password"
run 02.uploads_POST.sh now
expect "02: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm -f "${UC}/state.local.password" "${UC}/state.local.window"

echo "=== 2.0/01 the transfers ==="
printf '%s' "${WINDOW}" > "${UC}/state.local.window"
GET_BODY="$(body g3 "$(t20 3 0)")" run 2.0/01.transfers_GET.sh
expect "2.0/01: exit 0, one GET of the log of the account after the window, in order, with the fields it reads" \
    "${RC}:$(ucalls | grep -c "^GET ${BASE}/logs/transfers?account=example_rsb_a&fields=id,filename,status,resubmitted&sortByStartTime=ascending&limit=100&startTimeAfter=${WINDOW}$")" "0:1"
has "2.0/01: the count, the account and the window" "3 transfers of example_rsb_a after ${WINDOW}:"
has "2.0/01: each transfer, with its status and the flag" "  report_2.txt  Processed  resubmitted: false"
has "2.0/01: the id as it goes into a URL" "SWQgW21U1"
SWQ=$(printf 'Id [mTransferStatusId=t1, mTransferStartTime=1]' | base64 | tr -d '\n')
GET_BODY="$(body g3b "$(t20 3 0 | jq -c --arg id "${SWQ}" '.result[0].id.urlrepresentation = $id')")" run 2.0/01.transfers_GET.sh example_x
has "2.0/01: a chosen account is the one asked about" "transfers of example_x after"
has "2.0/01: and it decodes the id" "...which is the Base64 of: Id [mTransferStatusId=t1, mTransferStartTime=1]"
GET_BODY="$(body g0 "$(t20 0 0)")" run 2.0/01.transfers_GET.sh
expect "2.0/01: no transfer is exit 1" "${RC}" "1"
has "2.0/01: with a hint" "There are no transfers: run 02.uploads_POST.sh first."
GET_STATUS=500 GET_BODY="$(body g500 '{"message":"Server trouble"}')" run 2.0/01.transfers_GET.sh
has "2.0/01: a refused list shows its code and reason" "GET /logs/transfers: HTTP 500: Server trouble"
rm -f "${UC}/state.local.window"
GET_BODY="$(body g3c "$(t20 3 0)")" run 2.0/01.transfers_GET.sh
expect "2.0/01: with no window file the whole log of the account is asked" "$(ucalls | grep -c 'startTimeAfter')" "0"
for bad in "-x" "a b" "../x"; do run 2.0/01.transfers_GET.sh "${bad}"; expect "2.0/01: ACCOUNT '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"; done
run 2.0/01.transfers_GET.sh a b
expect "2.0/01: two parameters are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 2.0/02 the resubmit, one by one ==="
printf '%s' "${WINDOW}" > "${UC}/state.local.window"
GET_BODY="$(body r3 "$(t20 3 0)")" POST_BODY="$(body ok '{"message":"Transfer with id t1 was successfully resubmitted."}')" POST_STATUS=200 run 2.0/02.transfers_resubmit_POST.sh
expect "2.0/02: exit 0, one list and one POST for each transfer" "${RC}:$(ucalls | grep -c '^GET'):$(ucalls | grep -c '^POST')" "0:1:3"
expect "2.0/02: the list asks only what was not resubmitted, in the window" "$(ucalls | grep -c "logs/transfers?account=example_rsb_a&resubmitted=false&fields=id,filename&sortByStartTime=ascending&limit=100&startTimeAfter=${WINDOW}")" "1"
expect "2.0/02: each POST is the resubmit of one id, by its urlrepresentation" "$(ucalls | grep '^POST' | sed "s#POST ${BASE}/logs/transfers/##" | tr '\n' ' ')" "SWQgW21U1/operations?operation=resubmit SWQgW21U2/operations?operation=resubmit SWQgW21U3/operations?operation=resubmit "
expect "2.0/02: with the session and the csrfToken" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: csrfToken:'):$(printf '%s\n' "${OUT}" | grep -c '^COOKIE: ')" "3:5"
has "2.0/02: it says what it does to each" "report_2.txt: HTTP 200, Transfer with id t1 was successfully resubmitted."
has "2.0/02: and the totals" "3 resubmitted, 0 refused."
GET_BODY="$(body r3b "$(t20 3 0)")" POST_BODY="$(body no '{"validationErrors":["Transfer cannot be resubmitted"]}')" POST_STATUS=400 run 2.0/02.transfers_resubmit_POST.sh
expect "2.0/02: a refused transfer is exit 1, and the others are still tried" "${RC}:$(ucalls | grep -c '^POST')" "1:3"
has "2.0/02: with the reason and the totals" "0 resubmitted, 3 refused."
GET_BODY="$(body r3c "$(t20 3 0)")" POST_BODY="$(body ok2 '{"message":"was successfully resubmitted."}')" POST_SEQ="200 400 200" run 2.0/02.transfers_resubmit_POST.sh
has "2.0/02: one refused of three" "2 resubmitted, 1 refused."
GET_BODY="$(body r0 "$(t20 0 0)")" run 2.0/02.transfers_resubmit_POST.sh
expect "2.0/02: nothing to resubmit is exit 1, and no POST is made" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
has "2.0/02: it says so" "example_rsb_a has no transfer that was not resubmitted yet: nothing to do."
GET_STATUS=500 GET_BODY="$(body r500 '{"message":"boom"}')" run 2.0/02.transfers_resubmit_POST.sh
expect "2.0/02: a list that is refused is exit 1, no POST" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
run 2.0/02.transfers_resubmit_POST.sh -x
expect "2.0/02: a bad ACCOUNT is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 2.0/03 the check ==="
GET_BODY="$(body c6 "$(t20 6 3)")" run 2.0/03.check_GET.sh
expect "2.0/03: three flagged and three new is exit 0" "${RC}:$(ucalls | grep -c '^GET')" "0:1"
has "2.0/03: the counts" "6 transfers in the log: 3 flagged as resubmitted, 3 not flagged"
has "2.0/03: the verdict" "Every resubmitted transfer has a new transfer after it."
GET_BODY="$(body c4 "$(t20 4 3)")" run 2.0/03.check_GET.sh
expect "2.0/03: fewer new transfers than flagged is exit 1 after 30 rounds" "${RC}:$(ucalls | grep -c '^GET')" "1:30"
has "2.0/03: it says so" "After 30 seconds the log has fewer new transfers than resubmitted ones."
GET_BODY="$(body c3 "$(t20 3 0)")" run 2.0/03.check_GET.sh
expect "2.0/03: nothing flagged is exit 1 at once" "${RC}:$(ucalls | grep -c '^GET')" "1:1"
has "2.0/03: it says nothing was resubmitted" "Nothing was resubmitted."
run 2.0/03.check_GET.sh a b
expect "2.0/03: two parameters are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 1.4/01 the preview ==="
GET_BODY="$(body p3 "$(t14 3 0)")" run 1.4/01.transfers_GET.sh
expect "1.4/01: exit 0, one GET of /api/v1.4/transfers with the criteria of 02" "${RC}:$(calls | grep -c "^GET ${BASE14}/transfers?accountOrLogin=example_rsb_b&resubmitted=false&limit=100&startTimeAfter=${WINDOW}$")" "0:1"
expect "1.4/01: with Basic authentication and no session" "$(printf '%s\n' "${OUT}" | grep -c '^BASIC_AUTH: apiadmin:'):$(printf '%s\n' "${OUT}" | grep -c '^COOKIE: ')" "1:0"
has "1.4/01: it says what the call would touch" "would touch 3 transfers:"
has "1.4/01: and lists them from the 1.4 shape" "  report_1.txt  Processed  Incoming  resubmitted: false"
GET_BODY="$(body p0 '{"transferEntries":[]}')" run 1.4/01.transfers_GET.sh
expect "1.4/01: none is exit 1" "${RC}" "1"
GET_STATUS=400 GET_BODY="$(body p400 '{"validationErrors":["Parameter limit should be a positive integer."]}')" run 1.4/01.transfers_GET.sh
has "1.4/01: a refusal shows its reason" "GET /api/v1.4/transfers: HTTP 400: Parameter limit should be a positive integer."
run 1.4/01.transfers_GET.sh "x y"
expect "1.4/01: a bad ACCOUNT is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 1.4/02 the one call ==="
OKS='[{"status":"OK","message":"Transfer with id a was successfully resubmitted."},{"status":"OK","message":"Transfer with id b was successfully resubmitted."},{"status":"OK","message":"Transfer with id c was successfully resubmitted."}]'
POST_BODY="$(body b3 "${OKS}")" POST_STATUS=200 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: exit 0, ONE POST to /api/v1.4/transfers/resubmit with the criteria" "${RC}:$(calls | grep -c '^POST'):$(calls | grep -c "^POST ${BASE14}/transfers/resubmit?accountOrLogin=example_rsb_b&resubmitted=false&limit=100&startTimeAfter=${WINDOW}$")" "0:1:1"
expect "1.4/02: with Basic authentication, and no session" "$(printf '%s\n' "${OUT}" | grep -c '^BASIC_AUTH: apiadmin:'):$(printf '%s\n' "${OUT}" | grep -c '^COOKIE: ')" "1:0"
has "1.4/02: it prints each entry" "  OK: Transfer with id b was successfully resubmitted."
has "1.4/02: and the totals" "HTTP 200: 3 entries, 3 OK, 0 not OK."
POST_BODY="$(body b3e '[{"status":"OK","message":"a"},{"status":"ERROR","message":"Error while resubmitting transfer with id b"},{"status":"ERROR","message":"Error while resubmitting transfer with id c"}]')" POST_STATUS=200 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: a 200 that holds ERROR entries is exit 1" "${RC}" "1"
has "1.4/02: it counts them" "HTTP 200: 3 entries, 1 OK, 2 not OK."
has "1.4/02: and shows the ERROR" "  ERROR: Error while resubmitting transfer with id b"
POST_BODY="$(body b400 '{"validationErrors":["No transfers found for resubmit."]}')" POST_STATUS=400 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: nothing found is exit 1" "${RC}" "1"
has "1.4/02: with the server's words" "POST /api/v1.4/transfers/resubmit: HTTP 400: No transfers found for resubmit."
POST_BODY="$(body bobj '{"message":"surprise"}')" POST_STATUS=200 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: a 200 that is not a list is exit 1" "${RC}" "1"
has "1.4/02: and says so" "HTTP 200, but the answer is not a list of entries"
POST_BODY="$(body bempty '[]')" POST_STATUS=200 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: an empty list is exit 1, not a success" "${RC}" "1"
rm -f "${UC}/state.local.window"
POST_BODY="$(body b3w "${OKS}")" POST_STATUS=200 run 1.4/02.transfers_resubmit_POST.sh example_rsb_b
expect "1.4/02: with no window file the call still has the account criterion" "$(calls | grep -c 'POST .*transfers/resubmit?accountOrLogin=example_rsb_b&resubmitted=false&limit=100$')" "1"
run 1.4/02.transfers_resubmit_POST.sh
expect "1.4/02: no ACCOUNT is exit 2, nothing sent: the call is never made without a criterion" "${RC}:$(ncalls)" "2:0"
has "1.4/02: with the usage" "Usage: ./02.transfers_resubmit_POST.sh ACCOUNT"
run 1.4/02.transfers_resubmit_POST.sh ""
expect "1.4/02: an empty ACCOUNT is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
for bad in "-x" "a&b" "a b"; do run 1.4/02.transfers_resubmit_POST.sh "${bad}"; expect "1.4/02: ACCOUNT '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"; done
run 1.4/02.transfers_resubmit_POST.sh a b
expect "1.4/02: two parameters are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 1.4/03 the check ==="
printf '%s' "${WINDOW}" > "${UC}/state.local.window"
GET_BODY="$(body k6 "$(t14 6 3)")" run 1.4/03.check_GET.sh
expect "1.4/03: three flagged and three new is exit 0, read with the 1.4 GET" "${RC}:$(calls | grep -c "^GET ${BASE14}/transfers?accountOrLogin=example_rsb_b&limit=100&startTimeAfter=${WINDOW}$")" "0:1"
has "1.4/03: the counts" "6 transfers in the log: 3 flagged as resubmitted, 3 not flagged"
GET_BODY="$(body k4 "$(t14 4 3)")" run 1.4/03.check_GET.sh
expect "1.4/03: fewer new than flagged is exit 1 after 30 rounds" "${RC}:$(calls | grep -c '^GET')" "1:30"
GET_BODY="$(body k3 "$(t14 3 0)")" run 1.4/03.check_GET.sh
expect "1.4/03: nothing flagged is exit 1" "${RC}" "1"
run 1.4/03.check_GET.sh a b
expect "1.4/03: two parameters are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 99 the cleanup ==="
printf '%s' "${PW}" > "${UC}/state.local.password"
run 99.cleanup_DELETE.sh
expect "99: exit 0, a DELETE of each account by its exact name" "${RC}:$(ucalls | grep '^DELETE' | grep -v myself | sed "s#DELETE ${BASE}/##" | tr '\n' ' ')" "0:accounts/example_rsb_a accounts/example_rsb_b "
has "99: it says so" "The account example_rsb_b was deleted."
expect "99: the password, the window and the session files are gone" "$(ls "${UC}" | grep -c '^state.local\|^session.cookie')" "0"
has "99: it says the transfers stay" "The transfers stay in the transfer log."
DELETE_STATUS=404 run 99.cleanup_DELETE.sh
expect "99: accounts that are not there are 404, and still exit 0 (it can be run twice)" "${RC}" "0"
has "99: and it says so" "The account example_rsb_a was not there."
DELETE_STATUS=500 run 99.cleanup_DELETE.sh
expect "99: another answer is exit 1, and the files are removed all the same" "${RC}:$(ls "${UC}" | grep -c '^state.local.password')" "1:0"
has "99: it says which one" "The account example_rsb_a could not be deleted (HTTP 500): delete it by hand."
run 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 00 run_all ==="
run 00.run_all.sh now
expect "00: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
HEAD_STATUS=200 run 00.run_all.sh
expect "00: when step 01 fails it stops, says which, and the cleanup still runs" "${RC}" "1"
has "00: (the step)" "01.accounts_POST failed."
hasnt "00: (step 02 is not run)" "=== 02.uploads_POST ==="
has "00: (the cleanup runs)" "=== 99.cleanup_DELETE ==="

echo "=== the files and the README ==="
for f in 00.run_all 01.accounts_POST 02.uploads_POST 2.0/01.transfers_GET 2.0/02.transfers_resubmit_POST 2.0/03.check_GET 1.4/01.transfers_GET 1.4/02.transfers_resubmit_POST 1.4/03.check_GET 99.cleanup_DELETE; do
    [ -x "${UC_ROOT}/09-resubmit-transfers/${f}.sh" ] && pass "${f}.sh is there and executable" || fail "${f}.sh is missing or not executable"
done
for s in "${UC_ROOT}"/09-resubmit-transfers/*.sh "${UC_ROOT}"/09-resubmit-transfers/*/*.sh; do
    case "$(basename "${s}")" in lib.sh|00.*|99.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/[^ ,]*\.sh).*/\1/p' "${s}" | head -1)
    n="${s#"${UC_ROOT}/09-resubmit-transfers/"}"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done
python3 - "${README_FILE}" "${UC_ROOT}/09-resubmit-transfers" <<'PY' && pass "README: the sections, the steps are the files, the claims, the two ways in two folders" || fail "README: see above"
import os, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
folder = sys.argv[2]
for heading in ("## Which way", "## What a resubmit is", "## The steps", "## What stays after the cleanup", "## What is not covered"):
    assert heading in text, heading
for needle in ("`2.0`: one at a time", "`1.4`: one call", "POST /api/v2.0/logs/transfers/{id}/operations?operation=resubmit", "POST /api/v1.4/transfers/resubmit", "urlrepresentation",
               "every transfer in the log", "not tried, on purpose", "the call is 200 and the entry says `ERROR`", "a second run resubmits them", "exact name", "Parameter limit should be a positive integer.",
               "A failed transfer cannot be resubmitted", "isResubmittable", "the transfers after the time of step 02".replace("the transfers", "transfers").replace("after the time", "**after the time")):
    assert needle.lower() in text.lower() or needle.replace("**", "").lower() in text.lower(), needle
for name in re.findall(r"`((?:\d\.\d/)?\d\d\.[a-z]+_[a-z_A-Z]+)(?: [\[A-Z]+[^`]*)?`", text):
    assert os.path.exists(os.path.join(folder, name + ".sh")), name
assert os.path.isdir(os.path.join(folder, "2.0")) and os.path.isdir(os.path.join(folder, "1.4"))
assert "Admin/API 1.4" in text or "API%201.4" in text
PY

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_09: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_09: PASS"
