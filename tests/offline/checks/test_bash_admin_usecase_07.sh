#!/bin/bash
# ==============================================================================
# Run Admin/UseCases/07-usage-reporting against a stub curl, and check the calls each script makes: the method, the URL and the exact query it builds
# (the windows in RFC 2822, the dd/MM/yyyy days, isBillable, businessUnit, account), the bodies of the POSTs, the headers, what it prints about the answers, and its exit code.
#
# Part 1: 01 the settings (a secret is not printed); 02 the active users against the accounts, by day, by name; 03 the report, the sum of its days and the four refusals;
# 04 the billable count for each day, the three values of isBillable, accountName= against account=; 05 the report against the log. Part 2: 06 the units and the accounts
# (the bodies, the password, an object that exists); 07 the 100 uploads of six accounts (who, how many, the wait for the log); 08 the two global numbers; 09 the accounts of a unit;
# 10 one unit (the accounts must add up); 11 the table with the shares; 99 the exact names, twice; 00 failing fast and still cleaning up. Then the functions and the numbers
# of the README (the report function, the midnights, the table of days) and its claims.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_07"
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
cp -R "${UC_ROOT}/07-usage-reporting" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
EU="https://st.example.com:8443/api/v2.0"
UC="${WORK}/tree/UseCases/07-usage-reporting"
rm -f "${UC}"/state.local.* "${UC}/session.cookie.jar"
UNITS="example_use_bu1 example_use_bu2 example_use_bu3"
ACCOUNTS="example_use_a1 example_use_b1 example_use_c1 example_use_d1 example_use_e1 example_use_f1"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
RULE_N=0
rules() {
    local out="${WORK}/rules_${RANDOM}${RANDOM}.tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
SEQ_N=0
# seq_dir FILE...: a folder in which the Nth GET is answered with the Nth file (the check of the session is the first GET), the last repeating
seq_dir() {
    local d="${WORK}/seq_${RANDOM}${RANDOM}" n=0 f
    mkdir -p "${d}"
    for f in "$@"; do n=$((n + 1)); cp "${f}" "${d}/${n}.json"; done
    echo "${d}"
}
count_json() { echo "{\"resultSet\":{\"returnCount\":1,\"totalCount\":$1},\"result\":[]}"; }
count() { body "c_$1_${RANDOM}" "$(count_json "$1")"; }
list_json() {   # TOTAL NAME...
    local total="$1"; shift
    jq -cn --argjson total "${total}" '{resultSet: {returnCount: ($ARGS.positional | length), totalCount: $total}, result: [$ARGS.positional[] | {name: ., type: "user"}]}' --args "$@"
}
reset_counters() { rm -f "${WORK}"/ctr.*; }

# run SCRIPT [PARAMS]: with a session jar in place (the stub writes none). GET_BODY, RULES and SEQ set the answers.
run() {
    local rel="$1"; shift
    reset_counters
    touch "${UC}/session.cookie.jar"
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_GET_SEQUENCE="${SEQ:-}" STUB_COUNTER="${WORK}/ctr" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }      # without the check of the session that comes first (GET /myself)
ncalls() { calls | wc -l | tr -d ' '; }
# a window and a day are today's, so a test reads <T> and <D>
norm() { sed -E 's/[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}/<T>/g; s#[0-9]{2}/[0-9]{2}/[0-9]{4}#<D>#g'; }
ncall_list() { ucalls | norm | tr '\n' ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
hdrs_of() { printf '%s\n' "${OUT}" | awk -v M="$1" '/^HEADER:/ {b = b $0 "\n"} /^METHOD:/ {if ($2 == M) r = b; b = ""} END {printf "%s", r}' | sed 's/^HEADER: //'; }

echo "=== 01 the settings ==="
VERSION="$(body version '{"version":"5.5-20260924","serverType":"ST-Core-Server"}')"
OPTIONS="$(body options '{"resultSet":{"returnCount":4,"totalCount":4},"result":[{"name":"StatisticsSummaryReport.AutomaticReport","values":["true"]},{"name":"StatisticsSummaryReport.AutomaticReport.DaysToInclude","values":["3"]},{"name":"StatisticsSummaryReport.ClientSecret","values":["{AES128}9IaPNuCgr4bFnHLIDActZQ=="]},{"name":"StatisticsSummaryReport.FilePath","values":[""]}]}')"
RULES="$(rules 'configurations/options' "${OPTIONS}" 'version' "${VERSION}")" run 01.settings_GET.sh
expect "01: asks the release, then the settings with the name filter and a limit of 100" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/version GET ${BASE}/configurations/options?name=StatisticsSummaryReport*&limit=100 "
has "01: prints the release" "Release 5.5-20260924, ST-Core-Server"
has "01: counts the settings" "The 4 settings of the usage report:"
has "01: prints a setting and its value" "StatisticsSummaryReport.AutomaticReport.DaysToInclude = 3"
hasnt "01: does not print the secret" "9IaPNuCgr4bFnHLIDActZQ"
has "01: says that the secret is hidden" "StatisticsSummaryReport.ClientSecret = (hidden)"
has "01: says that an empty value is empty" "StatisticsSummaryReport.FilePath: (empty)"
RULES="$(rules 'configurations/options' "$(body no_options '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')" 'version' "${VERSION}")" run 01.settings_GET.sh
expect "01: no setting is exit 1" "${RC}" "1"
has "01: and it says why" "The server has no StatisticsSummaryReport* setting: this release has no usage report."
STUB_STATUS_GET_SEQ="200 403" GET_BODY="$(body forbidden '{"message":"Error validating request","validationErrors":["Access denied"]}')" run 01.settings_GET.sh
expect "01: a refused call is exit 1, after the session check and that one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
run 01.settings_GET.sh now
expect "01: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: with the usage" "Usage: ./01.settings_GET.sh"

echo "=== 02 the active users ==="
ACTIVE="$(body active "$(list_json 4 ann bob cy dee | jq -c '.result |= map(. + {lastAccessTime: "October 30, 2026, 9:30 AM"})')")"
ACCOUNTS_LIST="$(body accts "$(list_json 2 ann bob)")"
ONE_DAY="$(body day "$(list_json 1 cy | jq -c '.result |= map(. + {lastAccessTime: "October 30, 2026, 9:30 AM"})')")"
RULES="$(rules 'lastAccessTime.from=2026-10-30' "${ONE_DAY}" 'name=' "$(count 1)" 'accounts' "${ACCOUNTS_LIST}")" GET_BODY="${ACTIVE}" run 02.activeUsers_GET.sh 2026-10-30
expect "02: the list with no limit and with 1000, the accounts, the day, then the name filter twice" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/statisticsSummary/activeUsers GET ${BASE}/statisticsSummary/activeUsers?limit=1000 GET ${BASE}/accounts?limit=1000&fields=name GET ${BASE}/statisticsSummary/activeUsers?lastAccessTime.from=2026-10-30&lastAccessTime.to=2026-10-30&limit=1000 GET ${BASE}/statisticsSummary/activeUsers?name=n&limit=1 GET ${BASE}/statisticsSummary/activeUsers?name=*&limit=1 "
has "02: the first call is a page" "With no limit: returnCount 4, totalCount 4. One page is 100 names."
has "02: the second is the whole list" "With limit=1000: returnCount 4, totalCount 4."
has "02: names that are no account any more are counted by name (cy and dee)" "The server has 2 accounts today. Of the 4 names read, 2 are no longer an account: a deleted account stays in the list."
has "02: the day, as the server's day" "Last seen on 2026-10-30, the day of the server: 1."
has "02: shows the entry with its text of a time" "  cy  October 30, 2026, 9:30 AM"
has "02: says the name filter looks inside the name (the middle of ann is n)" "name=n (the middle of ann) found 1: the filter looks inside the name."
has "02: and that * is not a wildcard" "name=* found 1: * is a plain character here, not a wildcard."
LONG="$(body long '{"resultSet":{"returnCount":2,"totalCount":5},"result":[{"name":"ann"},{"name":"bob"}]}')"
GET_BODY="${LONG}" RULES="$(rules 'accounts' "${ACCOUNTS_LIST}" 'name=' "$(count 0)")" run 02.activeUsers_GET.sh
has "02: a list longer than one answer says to read it with offset" "The list is longer than one answer of 1000: read it with offset"
expect "02: the default day is today (the filter is there, yyyy-MM-dd)" "$(ucalls | grep -c 'lastAccessTime.from=[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}&lastAccessTime.to=')" "1"
STATUS_GET=500 GET_BODY="$(body err500 '{"message":"boom"}')" run 02.activeUsers_GET.sh
expect "02: a refused list is exit 1 after one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
for bad in 30/10/2026 2026-13 x; do
    run 02.activeUsers_GET.sh "${bad}"
    expect "02: a DAY of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "02: with the form it wants" "DAY is 'x': a day written yyyy-MM-dd"
run 02.activeUsers_GET.sh 2026-10-30 2026-10-31
expect "02: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 03 the report ==="
REPORT="$(body report '{"granularity":86400000,"report":{"2026-10-25T00:00:00.000+03:00":{"usage":{"ST.Transfers":1282,"ST.TransfersIn":774,"ST.TransfersOut":1089,"ST.ActiveUsers":0,"ST.Volume":0}},"2026-10-26T00:00:00.000+02:00":{"usage":{"ST.Transfers":88,"ST.TransfersIn":80,"ST.TransfersOut":30,"ST.ActiveUsers":0,"ST.Volume":0}}},"meta":{"productVersion":"5.5-20260924","reportTimeframe":{"startDate":"2026-10-25T00:00:00.000+03:00","endDate":"2026-10-27T00:00:00.000+02:00"},"reportSummary":{"ST.Transfers":1370,"ST.TransfersIn":854,"ST.TransfersOut":1119,"ST.ActiveUsers":0,"ST.Volume":0}}}')"
ERR_MANDATORY="$(body e1 "{\"message\":\"Error validating request\",\"validationErrors\":[\"'startDate' and 'endDate' parameters are mandatory.\"]}")"
ERR_FRAME="$(body e2 "{\"message\":\"Error validating request\",\"validationErrors\":[\"Incorrect date frame. 'startDate' must be before 'endDate'.\"]}")"
ERR_FORMAT="$(body e3 '{"message":"Error validating request","validationErrors":["Date 2026-10-23 is not in correct format. The correct format is: dd/MM/yyyy."]}')"
ERR_FUTURE="$(body e4 '{"message":"Error validating request","validationErrors":["An error occur while generating report for the following date frame: start date: 02/11/2026, end date: 03/11/2026."]}')"
MYSELF="$(body myself '{"loginName":"admin"}')"
SEQ="$(seq_dir "${MYSELF}" "${REPORT}" "${ERR_MANDATORY}" "${ERR_FRAME}" "${ERR_FORMAT}" "${ERR_FUTURE}")" STUB_STATUS_GET_SEQ="200 200 400 400 400 400" run 03.generateReport_GET.sh 25/10/2026 26/10/2026
expect "03: the report with both include flags, then the four refusals" "${RC}:$(ncall_list)" \
  "0:GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D>&includeActiveUsersCount=true&includeIncomingFileVolume=true GET ${BASE}/statisticsSummary/generateReport?startDate=<D> GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D> GET ${BASE}/statisticsSummary/generateReport?startDate=2026-10-23&endDate=2026-10-24 GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D> "
has "03: prints a day as the server names it, with its numbers" "  2026-10-25T00:00:00.000+03:00  1282  774  1089  0  0"
has "03: the offset changes between the two days" "  2026-10-26T00:00:00.000+02:00  88  80  30  0  0"
has "03: says the end of the time frame is the day after" "(the start of the day after the last day)"
has "03: prints the summary" "Summary: transfers 1370, in 854, out 1119, users 0, volume 0"
has "03: checks that the summary is the sum of the days" "The summary is the sum of the days."
has "03: says the counters stay 0 although asked for" "ST.ActiveUsers in the summary: 0, ST.Volume: 0, although both were asked for."
has "03: each refusal is shown with its message (mandatory)" "Refused, as it should be (no endDate): HTTP 400, 'startDate' and 'endDate' parameters are mandatory."
has "03: (frame)" "Refused, as it should be (startDate after endDate): HTTP 400, Incorrect date frame."
has "03: (format)" "Refused, as it should be (a day written yyyy-MM-dd): HTTP 400, Date 2026-10-23 is not in correct format."
has "03: (future)" "Refused, as it should be (a day in the future): HTTP 400, An error occur while generating report"
BAD_SUM="$(body badsum "$(jq -c '.meta.reportSummary["ST.Transfers"] = 1371' "${REPORT}")")"
SEQ="$(seq_dir "${MYSELF}" "${BAD_SUM}")" STUB_STATUS_GET_SEQ="200 200" run 03.generateReport_GET.sh 25/10/2026 26/10/2026
expect "03: a summary that is not the sum of the days is exit 1, before the refusals" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "03: and it says so" "The summary is NOT the sum of the days"
SEQ="$(seq_dir "${MYSELF}" "${REPORT}" "${ERR_MANDATORY}" "${ERR_FRAME}" "${ERR_FORMAT}" "${REPORT}")" STUB_STATUS_GET_SEQ="200 200 400 400 400 200" run 03.generateReport_GET.sh 25/10/2026 26/10/2026
expect "03: a refusal that answers 200 is exit 1" "${RC}" "1"
has "03: and it says which" "NOT refused as expected (a day in the future): HTTP 200"
SEQ="$(seq_dir "${MYSELF}" "${ERR_MANDATORY}")" STUB_STATUS_GET_SEQ="200 400" run 03.generateReport_GET.sh 25/10/2026 26/10/2026
expect "03: a report that is refused is exit 1, after that one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "03: with the code and the reason" "HTTP 400: 'startDate' and 'endDate' parameters are mandatory."
SEQ="$(seq_dir "${MYSELF}" "${REPORT}" "${ERR_MANDATORY}" "${ERR_FRAME}" "${ERR_FORMAT}" "${ERR_FUTURE}")" STUB_STATUS_GET_SEQ="200 200 400 400 400 400" run 03.generateReport_GET.sh
expect "03: with no dates it asks two days ago to today" "$(ucalls | sed -n 1p | norm)" "GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D>&includeActiveUsersCount=true&includeIncomingFileVolume=true"
for bad in 2026-10-25 25-10-2026 x; do
    run 03.generateReport_GET.sh "${bad}" 26/10/2026
    expect "03: a FROM of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "03: with the form it wants" "FROM is 'x': a day written dd/MM/yyyy"
run 03.generateReport_GET.sh 25/10/2026 y
has "03: and for TO" "TO is 'y': a day written dd/MM/yyyy"
run 03.generateReport_GET.sh 25/10/2026 26/10/2026 27/10/2026
expect "03: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 04 the billable count for each day ==="
LOG_WINDOW='startTimeAfter=<T>&endTimeBefore=<T>&limit=1&fields=id'
RULES="$(rules 'accountName=' "$(count 10)" 'account=example_use_no_such_account' "$(count 0)" 'isBillable=false' "$(count 2)" 'isBillable=true' "$(count 7)")" GET_BODY="$(count 10)" run 04.transfers_billable_count_GET.sh 2
expect "04: one billable call for each day, then the three values, then accountName= and account=" "${RC}:$(ncall_list)" \
  "0:GET ${BASE}/logs/transfers?isBillable=true&${LOG_WINDOW} GET ${BASE}/logs/transfers?isBillable=true&${LOG_WINDOW} GET ${BASE}/logs/transfers?startTimeAfter=<T>&endTimeBefore=<T>&limit=1&fields=id GET ${BASE}/logs/transfers?isBillable=true&${LOG_WINDOW} GET ${BASE}/logs/transfers?isBillable=false&${LOG_WINDOW} GET ${BASE}/logs/transfers?accountName=example_use_no_such_account&${LOG_WINDOW} GET ${BASE}/logs/transfers?account=example_use_no_such_account&${LOG_WINDOW} "
has "04: prints a day with its count" "  7"
has "04: prints the three values of isBillable and what is in neither" "10 transfers: 7 billable, 2 not billable, 1 with no value (in neither count)."
has "04: shows that accountName= is not a filter" "accountName=example_use_no_such_account found 10 of the 10: accountName is not a filter, and every transfer came back."
has "04: and that account= is" "account=example_use_no_such_account found 0: account is the filter."
expect "04: the days are two midnights apart: consecutive days, each window starts where the one before ended" "$(printf '%s\n' "${OUT}" | grep -c '^URL: .*isBillable=true&startTimeAfter=.* 00:00:00 [+-][0-9]*&endTimeBefore=.* 00:00:00 ')" "3"
TWO_DAYS_FIRST_END=$(printf '%s\n' "${OUT}" | grep '^URL: .*isBillable=true&startTimeAfter' | sed -n 1p | sed -E 's/.*endTimeBefore=([^&]*)&limit.*/\1/')
TWO_DAYS_SECOND_START=$(printf '%s\n' "${OUT}" | grep '^URL: .*isBillable=true&startTimeAfter' | sed -n 2p | sed -E 's/.*startTimeAfter=([^&]*)&endTimeBefore.*/\1/')
expect "04: the second day starts at the midnight that ended the first" "${TWO_DAYS_SECOND_START}" "${TWO_DAYS_FIRST_END}"
RET_ONE="$(body ret1 '{"resultSet":{"returnCount":1,"totalCount":5},"result":[{"id":{}}]}')"
GET_BODY="${RET_ONE}" run 04.transfers_billable_count_GET.sh 1
has "04: a day is counted with totalCount (5), and not with returnCount (1)" "  5"
GET_BODY="${RET_ONE}" run 04.transfers_billable_count_GET.sh 1 john
expect "04: an ACCOUNT is sent as account= in the day and in the three values (4 calls), and not in the two demonstration calls" "$(ucalls | grep -c 'account=john&')/$(ucalls | grep -c 'logs/transfers')" "4/6"
has "04: and named in the heading" "Billable transfers for each day, for john:"
GET_BODY="$(body nototal '{"resultSet":{"returnCount":1},"result":[]}')" run 04.transfers_billable_count_GET.sh 1
expect "04: an answer with no totalCount is exit 1 after one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "04: and it says there is nothing to count" "the answer has no resultSet.totalCount, so there is nothing to count."
STUB_STATUS_GET_SEQ="200 403" GET_BODY="$(body forb '{"message":"Error validating request","validationErrors":["Access denied"]}')" run 04.transfers_billable_count_GET.sh 2
expect "04: a refused day is exit 1, and the total is not printed" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "04: with the code and the reason" "HTTP 403: Access denied"
for bad in 0 x -2 1.5; do
    run 04.transfers_billable_count_GET.sh "${bad}"
    expect "04: DAYS of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "04: with the reason" "DAYS is '1.5': it must be a whole number of 1 or more."
run 04.transfers_billable_count_GET.sh 1 john extra
expect "04: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 05 the report against the log ==="
rep() { body "rep_$1" "{\"meta\":{\"reportSummary\":{\"ST.Transfers\":$1}}}"; }
SEQ="$(seq_dir "${MYSELF}" "$(rep 7)" "$(count 7)" "$(rep 5)" "$(count 9)")" run 05.report_vs_log.sh 2
expect "05: for each day the report of that day, then the billable count of the same day" "${RC}:$(ncall_list)" \
  "0:GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D> GET ${BASE}/logs/transfers?isBillable=true&${LOG_WINDOW} GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D> GET ${BASE}/logs/transfers?isBillable=true&${LOG_WINDOW} "
expect "05: the first day is equal (+0), the second is 4 more in the log (+4)" "$(printf '%s\n' "${OUT}" | grep -E '^[0-9]{2}/[0-9]{2}/[0-9]{4} ' | awk '{print $2 "/" $3 "/" $4}' | tr '\n' ' ')" "7/7/+0 5/9/+4 "
has "05: says on how many days they are equal" "The two are equal on 1 of 2 days."
has "05: and where the numbers of an invoice come from" "Take the numbers for a report or an invoice from the report"
SEQ="$(seq_dir "${MYSELF}" "$(body noST '{"meta":{"reportSummary":{}}}')")" run 05.report_vs_log.sh 1
expect "05: a report with no ST.Transfers is exit 1" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "05: and it says so" "has no ST.Transfers."
SEQ="$(seq_dir "${MYSELF}" "${ERR_FRAME}")" STUB_STATUS_GET_SEQ="200 400" run 05.report_vs_log.sh 1
expect "05: a refused report is exit 1, with the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 400: Incorrect date frame')" "1:1"
run 05.report_vs_log.sh 0
expect "05: DAYS of 0 is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 05.report_vs_log.sh 1 2
expect "05: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 06 the units and the accounts ==="
rm -f "${UC}/state.local.password"
STATUS_HEAD=404
run_post() { STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 STUB_LOCATION_PREFIX=x_ run "$@"; }
run_post 06.business_units_POST.sh
expect "06: nine HEAD checks (3 units, 6 accounts), then 3 unit POSTs and 6 account POSTs, in that order, exit 0" "${RC}:$(ucalls | awk '{print $1 " " $2}' | sed "s#${BASE}/##" | tr '\n' ' ')" \
  "0:HEAD businessUnits/example_use_bu1 HEAD businessUnits/example_use_bu2 HEAD businessUnits/example_use_bu3 HEAD accounts/example_use_a1 HEAD accounts/example_use_b1 HEAD accounts/example_use_c1 HEAD accounts/example_use_d1 HEAD accounts/example_use_e1 HEAD accounts/example_use_f1 POST businessUnits POST businessUnits POST businessUnits POST accounts POST accounts POST accounts POST accounts POST accounts POST accounts "
expect "06: the first unit is posted with its name and the base folder under /home" "$(payload 1)" '{"name":"example_use_bu1","baseFolder":"/home/example_use_bu1"}'
PASSWORD_SENT=$(payload 4 | jq -r '.user.passwordCredentials.password')
expect "06: the first account is in its unit, with the home folder under the unit, and the fixed user id and group" "$(payload 4 | jq -c 'del(.user)')" \
  '{"name":"example_use_a1","type":"user","businessUnit":"example_use_bu1","homeFolder":"/home/example_use_bu1/example_use_a1","uid":"57101","gid":"57101"}'
expect "06: the user name of the account is its name" "$(payload 4 | jq -r '.user.name')" "example_use_a1"
expect "06: the second account of a unit has its own uid and the unit's gid" "$(payload 5 | jq -c '[.uid, .gid, .businessUnit]')" '["57201","57101","example_use_bu1"]'
expect "06: the first account of the second unit" "$(payload 6 | jq -c '[.name, .uid, .gid, .businessUnit]')" '["example_use_c1","56405","56405","example_use_bu2"]'
expect "06: the last account is in the third unit" "$(payload 9 | jq -c '[.name, .uid, .gid, .businessUnit]')" '["example_use_f1","57601","57501","example_use_bu3"]'
expect "06: one password for the six accounts" "$(for n in 4 5 6 7 8 9; do payload "${n}" | jq -r '.user.passwordCredentials.password'; done | sort -u | wc -l | tr -d ' ')" "1"
expect "06: the password in state.local.password is the one that was sent" "$(cat "${UC}/state.local.password")" "${PASSWORD_SENT}"
expect "06: and only the owner can read that file" "$(stat -f %Lp "${UC}/state.local.password" 2>/dev/null || stat -c %a "${UC}/state.local.password")" "600"
expect "06: a POST carries the csrfToken, Referer and Content-Type" "$(hdrs_of POST | grep -c '^Content-Type: application/json')" "1"
has "06: says where the first unit is" "HTTP 201, it is at ${BASE}/businessUnits/x_1"
rm -f "${UC}/state.local.password"
STUB_STATUS_HEAD_SEQ="404 404 404 404 200" STUB_STATUS_POST=201 run 06.business_units_POST.sh
expect "06: an account that exists stops it, exit 1, before any POST" "${RC}:$(ucalls | grep -c POST)" "1:0"
has "06: it says which and what to do" "example_use_b1 exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."
expect "06: and no password was kept" "$([ -e "${UC}/state.local.password" ] && echo kept || echo none)" "none"
STUB_STATUS_HEAD=500 run 06.business_units_POST.sh
expect "06: a HEAD that is neither 200 nor 404 is exit 1, nothing created" "${RC}:$(ucalls | grep -c POST)" "1:0"
has "06: and it says so" "Could not tell whether businessUnits/example_use_bu1 exists (HTTP 500). Nothing more was created."
MSG400="$(body m400 '{"message":"Error validating request","validationErrors":["The business unit name is not unique."]}')"
STUB_STATUS_HEAD=404 STUB_STATUS_POST=400 STUB_CURL_POST_BODY="${MSG400}" run 06.business_units_POST.sh
expect "06: a POST that is refused is exit 1, after that one POST" "${RC}:$(ucalls | grep -c POST)" "1:1"
has "06: with the code and the reason" "POST /businessUnits: HTTP 400"
has "06: (the reason)" "The business unit name is not unique."
expect "06: and no password was kept" "$([ -e "${UC}/state.local.password" ] && echo kept || echo none)" "none"
run 06.business_units_POST.sh now
expect "06: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 07 the 100 uploads ==="
echo "Ex1!testpassword1" > "${UC}/state.local.password"
BU_RULES() { rules generateReport "${TODAY_REPORT}" 'businessUnit=example_use_bu1' "$(count "$1")" 'businessUnit=example_use_bu2' "$(count "$2")" 'businessUnit=example_use_bu3' "$(count "$3")"; }
TODAY_REPORT="$(rep 510)"
GET_BODY="${MYSELF}"
RULES="$(BU_RULES 40 35 25)" STUB_STATUS_POST=201 run 07.transfers_make_POST.sh
expect "07: exit 0" "${RC}" "0"
expect "07: after the session check, the report of today, then the uploads, then the log of each unit" "$(ucalls | awk '{print $1}' | uniq -c | awk '{print $2 ":" $1}' | tr '\n' ' ')" "GET:1 POST:100 GET:3 "
expect "07: the report is asked for one day, today" "$(ucalls | sed -n 1p | norm)" "GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D>"
expect "07: the uploads go to the End User API, to /files" "$(ucalls | grep '^POST' | grep -c "^POST ${EU}/files$")" "100"
expect "07: each account makes its own number of uploads (25 15 20 15 15 10)" "$(for a in $ACCOUNTS; do printf '%s ' "$(printf '%s\n' "${OUT}" | grep -c "^BASIC_AUTH: ${a}:Ex1!testpassword1")"; done)" "25 15 20 15 15 10 "
expect "07: 100 uploads in all" "$(printf '%s\n' "${OUT}" | grep -c '^FORM: file=@.*;filename=use_[0-9]*.txt')" "100"
expect "07: the files of an account are numbered from 1" "$(printf '%s\n' "${OUT}" | grep '^FORM:' | sed -n '1p;25p;26p' | sed -E 's/.*filename=//' | tr '\n' ' ')" "use_1.txt use_25.txt use_1.txt "
expect "07: the log is asked for each unit with the window that was kept" "$(ucalls | grep '^GET' | tail -3 | sed -E 's#^GET .*businessUnit=([a-z0-9_]*)&startTimeAfter=.*&limit=1&fields=id$#\1#' | tr '\n' ' ')" "example_use_bu1 example_use_bu2 example_use_bu3 "
has "07: reports the three counts" "The log shows: example_use_bu1=40 example_use_bu2=35 example_use_bu3=25."
expect "07: the window is two seconds before the first upload, in RFC 2822" "$(cat "${UC}/state.local.window" | norm)" "<T>"
expect "07: the report of today is kept with its day" "$(cut -d' ' -f2 "${UC}/state.local.report")" "510"
expect "07: (the day)" "$(cut -d' ' -f1 "${UC}/state.local.report" | norm)" "<D>"
has "07: says what the report said before" "says ST.Transfers 510 before the users work"
RULES="$(BU_RULES 40 30 25)" STUB_STATUS_POST=201 run 07.transfers_make_POST.sh
expect "07: a log that never shows the transfers is exit 1" "${RC}" "1"
has "07: after 60 rounds, it says what it saw and what it expected" "After 60 seconds the log shows: example_use_bu1=40 example_use_bu2=30 example_use_bu3=25. Expected 40, 35 and 25."
expect "07: 60 rounds of 3 calls" "$(ucalls | grep -c 'businessUnit=')" "180"
RULES="$(BU_RULES 40 35 25)" STUB_STATUS_POST_SEQ="201 201 403" run 07.transfers_make_POST.sh
expect "07: an upload that is refused is exit 1, and the next is not tried" "${RC}:$(ucalls | grep -c '^POST')" "1:3"
has "07: with its name and code" "example_use_a1 uploads use_3.txt: HTTP 403"
RULES="$(BU_RULES 40 35 25)" STUB_STATUS_POST=000 run 07.transfers_make_POST.sh
expect "07: no answer is exit 1 and names the End User port" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'The End User API has its own port: set ST_ENDUSER_PORT')" "1:1"
RULES="$(rules generateReport "${ERR_FRAME}")" STUB_STATUS_GET_SEQ="200 400" run 07.transfers_make_POST.sh
expect "07: a report that is refused is exit 1, before any upload" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
RULES="$(rules generateReport "$(body noST2 '{"meta":{"reportSummary":{}}}')")" run 07.transfers_make_POST.sh
expect "07: a report with no ST.Transfers is exit 1" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
rm -f "${UC}/state.local.password"
run 07.transfers_make_POST.sh
expect "07: with no password file it is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "07: and says to run 06" "run 06.business_units_POST.sh first"
echo x > "${UC}/state.local.password"
run 07.transfers_make_POST.sh now
expect "07: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 08 the two global numbers ==="
echo "Ex1!x" > "${UC}/state.local.password"
printf 'Fri, 30 Oct 2026 09:39:03 +0200\n' > "${UC}/state.local.window"
printf '30/10/2026 510\n' > "${UC}/state.local.report"
RULES="$(rules 'businessUnit=' "$(rep 610)" 'generateReport' "$(rep 610)" 'isBillable=true' "$(count 100)")" GET_BODY="${MYSELF}" run 08.global_total_GET.sh
expect "08: the billable count after the kept window, the report of the kept day, and the report with a business unit" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/logs/transfers?isBillable=true&startTimeAfter=Fri, 30 Oct 2026 09:39:03 +0200&limit=1&fields=id GET ${BASE}/statisticsSummary/generateReport?startDate=30/10/2026&endDate=30/10/2026 GET ${BASE}/statisticsSummary/generateReport?startDate=$(date +%d/%m/%Y)&endDate=$(date +%d/%m/%Y)&businessUnit=example_use_bu1 "
expect "08: (the third call has a day of today)" "$(ucalls | sed -n 3p | norm)" "GET ${BASE}/statisticsSummary/generateReport?startDate=<D>&endDate=<D>&businessUnit=example_use_bu1"
has "08: the log says 100 billable transfers" "after Fri, 30 Oct 2026 09:39:03 +0200: 100 billable transfers."
has "08: the report says how much more than before" "ST.Transfers was 510 before the users worked and is 610 now: 100 more."
has "08: shows that the report ignores a business unit" "The report has no business unit: that parameter is ignored, and the number is the whole server's."
has "08: points to the next steps" "09 to 11 ask the transfer log"
rm -f "${UC}/state.local.report"
RULES="$(rules 'isBillable=true' "$(count 3)" 'generateReport' "$(rep 610)")" GET_BODY="${MYSELF}" run 08.global_total_GET.sh "Fri, 30 Oct 2026 01:00:00 +0200"
expect "08: with no report kept it asks only the log and the one report with the unit, and says to run 07" "${RC}:$(ucalls | wc -l | tr -d ' '):$(printf '%s\n' "${OUT}" | grep -c 'There is no state.local.report: run 07')" "0:2:1"
expect "08: a FROM that is given is the window" "$(ucalls | sed -n 1p)" "GET ${BASE}/logs/transfers?isBillable=true&startTimeAfter=Fri, 30 Oct 2026 01:00:00 +0200&limit=1&fields=id"
rm -f "${UC}/state.local.window"
RULES="$(rules 'isBillable=true' "$(count 3)" 'generateReport' "$(rep 610)")" GET_BODY="${MYSELF}" run 08.global_total_GET.sh
expect "08: with no window kept it is midnight today" "$(ucalls | sed -n 1p | norm)" "GET ${BASE}/logs/transfers?isBillable=true&startTimeAfter=<T>&limit=1&fields=id"
expect "08: (an RFC 2822 midnight)" "$(ucalls | sed -n 1p | grep -c 'startTimeAfter=[A-Z][a-z][a-z], [0-9][0-9] [A-Z][a-z][a-z] [0-9]\{4\} 00:00:00 [+-][0-9]\{4\}&')" "1"
printf '30/10/2026 510\n' > "${UC}/state.local.report"; printf 'Fri, 30 Oct 2026 09:39:03 +0200\n' > "${UC}/state.local.window"
STUB_STATUS_GET_SEQ="200 403" GET_BODY="$(body forb2 '{"validationErrors":["Access denied"]}')" run 08.global_total_GET.sh
expect "08: a refused log count is exit 1 after one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
RULES="$(rules 'isBillable=true' "$(count 100)" 'generateReport' "$(body noST3 '{"meta":{"reportSummary":{}}}')")" GET_BODY="${MYSELF}" run 08.global_total_GET.sh
expect "08: a report with no ST.Transfers is exit 1" "${RC}" "1"
for bad in "yesterday" "30/10/2026"; do
    run 08.global_total_GET.sh "${bad}"
    expect "08: a FROM of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "08: with the form it wants" "FROM is '30/10/2026': a time in RFC 2822 with its offset"
run 08.global_total_GET.sh a b
expect "08: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 09 the accounts of a unit ==="
BU_ACCOUNTS="$(body bua "$(jq -cn '{resultSet:{returnCount:2,totalCount:2},result:[{name:"example_use_a1",businessUnit:"example_use_bu1",homeFolder:"/home/example_use_bu1/example_use_a1"},{name:"example_use_b1",businessUnit:"example_use_bu1",homeFolder:"/home/example_use_bu1/example_use_b1"}]}')")"
RULES="$(rules 'accounts?businessUnit' "${BU_ACCOUNTS}" 'logs/transfers' "$(count 40)")" GET_BODY="${MYSELF}" run 09.business_unit_accounts_GET.sh
expect "09: the accounts of the default unit with the fields, then the log with the unit" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts?businessUnit=example_use_bu1&limit=1000&fields=name,businessUnit,homeFolder GET ${BASE}/logs/transfers?businessUnit=example_use_bu1&limit=1&fields=id "
has "09: counts the accounts" "The business unit example_use_bu1 has 2 accounts:"
has "09: shows an account with its unit and home" "  example_use_a1  businessUnit example_use_bu1  home /home/example_use_bu1/example_use_a1"
has "09: shows what the log knows of the unit" "The transfer log knows the unit: 40 transfers in all"
NO_ACCOUNTS="$(body noacc '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')"
NO_UNIT="$(body nounit '{"message":"Error validating request","validationErrors":["Cannot find business unit with name nosuch."]}')"
RULES="$(rules 'accounts?businessUnit' "${NO_ACCOUNTS}" 'logs/transfers' "${NO_UNIT}")" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 200 404" run 09.business_unit_accounts_GET.sh nosuch
expect "09: a unit that does not exist: the accounts say 200 and none, the log says 404, and it is exit 0" "${RC}:$(ucalls | grep -c 'businessUnit=nosuch')" "0:2"
has "09: shows the 404 of the log with its reason" "The transfer log does not know a business unit nosuch: HTTP 404, Cannot find business unit with name nosuch."
has "09: and says that an empty account list proves nothing" "an empty answer does not prove that the unit is there."
RULES="$(rules 'accounts?businessUnit' "$(body e400 '{"validationErrors":["bad"]}')")" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 400" run 09.business_unit_accounts_GET.sh
expect "09: a refused account list is exit 1 after one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
RULES="$(rules 'accounts?businessUnit' "${BU_ACCOUNTS}" 'logs/transfers' "$(body e500 '{"message":"boom"}')")" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 200 500" run 09.business_unit_accounts_GET.sh
expect "09: a log that answers 500 is exit 1" "${RC}" "1"
RULES="$(rules 'accounts?businessUnit' "${BU_ACCOUNTS}" 'logs/transfers' "$(count 40)")" GET_BODY="${MYSELF}" run 09.business_unit_accounts_GET.sh 'Unit with space'
expect "09: a unit with a space is sent as it is, for curl to encode" "$(ucalls | sed -n 1p)" "GET ${BASE}/accounts?businessUnit=Unit with space&limit=1000&fields=name,businessUnit,homeFolder"
run 09.business_unit_accounts_GET.sh -x
expect "09: a unit that starts with a dash is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 09.business_unit_accounts_GET.sh a b
expect "09: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 10 one unit ==="
BU_NAMES="$(body bun "$(list_json 2 example_use_a1 example_use_b1)")"
ACTIVE2="$(body active2 "$(list_json 3 example_use_a1 zed example_use_zz)")"
unit_rules() {    # TOTAL BILLABLE INCOMING A1_ALL A1_BILL B1_ALL B1_BILL
    rules 'account=example_use_a1&isBillable=true' "$(count "$5")" 'account=example_use_a1&' "$(count "$4")" 'account=example_use_b1&isBillable=true' "$(count "$7")" 'account=example_use_b1&' "$(count "$6")" \
          'incoming=true' "$(count "$3")" 'isBillable=true&businessUnit' "$(count "$2")" 'businessUnit=example_use_bu1&startTimeAfter' "$(count "$1")" 'accounts?businessUnit' "${BU_NAMES}" 'activeUsers' "${ACTIVE2}"
}
RULES="$(unit_rules 40 40 40 25 25 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh example_use_bu1 "Fri, 30 Oct 2026 09:39:03 +0200"
W='startTimeAfter=Fri, 30 Oct 2026 09:39:03 +0200'
expect "10: the accounts, the unit's total, billable and incoming, then two calls for each account, then the active users" "${RC}:$(ucalls | sed "s#${BASE}/##" | tr '\n' ' ')" \
  "0:GET accounts?businessUnit=example_use_bu1&limit=1000&fields=name GET logs/transfers?businessUnit=example_use_bu1&${W}&limit=1&fields=id GET logs/transfers?isBillable=true&businessUnit=example_use_bu1&${W}&limit=1&fields=id GET logs/transfers?incoming=true&businessUnit=example_use_bu1&${W}&limit=1&fields=id GET logs/transfers?account=example_use_a1&${W}&limit=1&fields=id GET logs/transfers?account=example_use_a1&isBillable=true&${W}&limit=1&fields=id GET logs/transfers?account=example_use_b1&${W}&limit=1&fields=id GET logs/transfers?account=example_use_b1&isBillable=true&${W}&limit=1&fields=id GET statisticsSummary/activeUsers?limit=1000 "
has "10: the unit as the log sees it" "The log, with businessUnit=example_use_bu1: 40 transfers, 40 billable, 40 incoming."
has "10: each account" "  example_use_a1: 25 transfers, 25 billable"
has "10: the accounts add up" "The accounts add up to the unit."
has "10: the last line, with the active users counted by exact name (only a1 of the two accounts is in the list)" "Business unit example_use_bu1: 2 accounts, 40 transfers, 40 billable (40 incoming), 1 active users."
RULES="$(unit_rules 40 40 40 25 24 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh example_use_bu1 "Fri, 30 Oct 2026 09:39:03 +0200"
expect "10: accounts that do not add up to the unit are exit 1" "${RC}" "1"
has "10: and it says what differs" "The accounts do not add up to the unit: 40 transfers and 39 billable for the accounts, 40 and 40 for the unit."
RULES="$(unit_rules 41 40 40 25 25 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh example_use_bu1 "Fri, 30 Oct 2026 09:39:03 +0200"
expect "10: a unit that has more transfers than its accounts is exit 1" "${RC}" "1"
printf 'Fri, 30 Oct 2026 09:39:03 +0200\n' > "${UC}/state.local.window"
RULES="$(unit_rules 40 40 40 25 25 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh
expect "10: with no parameters it is the first unit and the window that 07 kept" "$(ucalls | sed -n 2p)" "GET ${BASE}/logs/transfers?businessUnit=example_use_bu1&${W}&limit=1&fields=id"
rm -f "${UC}/state.local.window"
RULES="$(unit_rules 40 40 40 25 25 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh example_use_bu1
expect "10: with no window kept it is midnight today" "$(ucalls | sed -n 2p | norm)" "GET ${BASE}/logs/transfers?businessUnit=example_use_bu1&startTimeAfter=<T>&limit=1&fields=id"
RULES="$(rules 'accounts?businessUnit' "${NO_ACCOUNTS}" 'logs/transfers' "${NO_UNIT}")" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 200 404" run 10.usage_per_business_unit_GET.sh nosuch
expect "10: a unit the log does not know is exit 1, with the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'the transfers of nosuch: HTTP 404: Cannot find business unit with name nosuch.')" "1:1"
RULES="$(rules 'accounts?businessUnit' "$(body e401 '{"validationErrors":["x"]}')")" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 400" run 10.usage_per_business_unit_GET.sh
expect "10: a refused account list is exit 1" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
RULES="$(unit_rules 40 40 40 25 25 15 15)" GET_BODY="${MYSELF}" run 10.usage_per_business_unit_GET.sh example_use_bu1 "30/10/2026"
expect "10: a FROM that is not RFC 2822 is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 10.usage_per_business_unit_GET.sh a "Fri, 30 Oct 2026 09:39:03 +0200" c
expect "10: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 11 the table ==="
all_rules() {    # SERVER_BILLABLE
    rules 'accounts?limit=1' "$(count 23)" 'accounts?businessUnit=example_use_bu1' "$(count 2)" 'accounts?businessUnit=example_use_bu2' "$(count 2)" 'accounts?businessUnit=example_use_bu3' "$(count 2)" 'businessUnits?limit=1000' "$(body bus "$(list_json 3 example_use_bu1 example_use_bu2 example_use_bu3)")" \
          'businessUnit=example_use_bu1&isBillable' "$(count 40)" 'businessUnit=example_use_bu1&' "$(count 40)" 'businessUnit=example_use_bu2&isBillable' "$(count 35)" 'businessUnit=example_use_bu2&' "$(count 35)" \
          'businessUnit=example_use_bu3&isBillable' "$(count 25)" 'businessUnit=example_use_bu3&' "$(count 25)" 'logs/transfers?isBillable=true' "$(count "$1")" 'logs/transfers?startTimeAfter' "$(count "$(( $1 + 5 ))")"
}
RULES="$(all_rules 100)" GET_BODY="${MYSELF}" run 11.usage_all_business_units_GET.sh "Fri, 30 Oct 2026 09:39:03 +0200"
expect "11: the server first (billable, all, accounts), then the units, then each unit's accounts, transfers and billable" "${RC}:$(ucalls | sed "s#${BASE}/##; s#${W}#W#" | head -4 | tr '\n' ' ')" \
  "0:GET logs/transfers?isBillable=true&W&limit=1&fields=id GET logs/transfers?W&limit=1&fields=id GET accounts?limit=1&fields=name GET businessUnits?limit=1000&fields=name "
expect "11: 3 calls for each unit" "$(ucalls | grep -c 'businessUnit=example_use_bu\|accounts?businessUnit=')" "9"
has "11: the header of the table" "  Business unit             Accounts  Transfers  Billable    Share"
has "11: a unit with its share of the server's billable transfers (40 of 100)" "  example_use_bu1                  2         40        40   40.0%"
has "11: (35 of 100)" "  example_use_bu2                  2         35        35   35.0%"
has "11: (25 of 100)" "  example_use_bu3                  2         25        25   25.0%"
has "11: the sum of the units" "  all the units                    6        100       100  100.0%"
has "11: what is in no unit" "  in no business unit             17          5         0    0.0%"
has "11: the whole server" "  the whole server                23        105       100  100.0%"
has "11: the units add up to the whole" "The units add up to all 100 billable transfers of the server in this window"
RULES="$(all_rules 110)" GET_BODY="${MYSELF}" run 11.usage_all_business_units_GET.sh "Fri, 30 Oct 2026 09:39:03 +0200"
has "11: transfers of accounts in no unit are a share of their own (10 of 110)" "  in no business unit             17         15        10    9.1%"
has "11: and the line says how many and that the report cannot tell the units apart" "The units add up to 100 of the 110 billable transfers of the server. The other 10 belong to accounts that are in no business unit"
has "11: (the report)" "The report cannot tell the units apart, and the sum of the units is not the report."
RULES="$(all_rules 0)" GET_BODY="${MYSELF}" run 11.usage_all_business_units_GET.sh "Fri, 30 Oct 2026 09:39:03 +0200"
has "11: a share of a total of 0 is a dash, not a division by zero" "  the whole server                23          5         0       -"
RULES="$(all_rules 100)" GET_BODY="${MYSELF}" STUB_STATUS_GET_SEQ="200 200 403" run 11.usage_all_business_units_GET.sh "Fri, 30 Oct 2026 09:39:03 +0200"
expect "11: a refused count is exit 1 after two calls" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:2"
RULES="$(all_rules 100)" GET_BODY="${MYSELF}" run 11.usage_all_business_units_GET.sh "30/10/2026"
expect "11: a FROM that is not RFC 2822 is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 11.usage_all_business_units_GET.sh a b
expect "11: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 99 the cleanup ==="
echo tok77 > "${UC}/state.local.csrf"
echo "Ex1!x" > "${UC}/state.local.password"
STUB_STATUS_HEAD=404 STUB_STATUS_DELETE=204 run 99.cleanup_DELETE.sh
expected=""
for a in ${ACCOUNTS}; do expected="${expected}HEAD ${BASE}/accounts/${a} DELETE ${BASE}/accounts/${a} "; done
for u in ${UNITS}; do expected="${expected}DELETE ${BASE}/businessUnits/${u} "; done
expect "99: for each account a HEAD and a DELETE by name, then the three units by name, then the session" "${RC}:$(ucalls | tr '\n' ' ')" "0:${expected}DELETE ${BASE}/myself "
has "99: says what it deleted" "The account example_use_f1 was deleted."
has "99: and the units" "The business unit example_use_bu3 was deleted."
has "99: and that the transfers stay" "Cleaned up. The transfers stay in the transfer log."
expect "99: a DELETE carries the csrfToken" "$(hdrs_of DELETE | grep -c '^csrfToken: tok77')" "1"
expect "99: the state files are gone (session, csrf, password)" "$(ls "${UC}"/session.cookie.jar "${UC}"/state.local.* 2>/dev/null | wc -l | tr -d ' ')" "0"
echo tok77 > "${UC}/state.local.csrf"; echo "Ex1!x" > "${UC}/state.local.password"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=204 GET_BODY="$(body emptyhome '{"files":[],"self":{}}')" run 99.cleanup_DELETE.sh
expect "99: an account that is there has its home folder read as the account on the End User API before it is deleted" "$(printf '%s\n' "${OUT}" | grep -c "^BASIC_AUTH: example_use_a1:Ex1!x")" "1"
has "99: and says what it emptied" "Emptied the home folder of example_use_a1: 0 entries removed."
expect "99: the home folders are read at the End User port" "$(ucalls | grep -c "^GET ${EU}/files")" "6"
echo "Ex1!x" > "${UC}/state.local.password"
STUB_STATUS_HEAD=404 STUB_STATUS_DELETE=404 run 99.cleanup_DELETE.sh
expect "99: objects that are not there are 404, said nothing about, exit 0" "${RC}" "0"
hasnt "99: nothing is said about an account that was not there" "The account example_use_a1"
STUB_STATUS_HEAD=404 STUB_STATUS_DELETE=500 run 99.cleanup_DELETE.sh
expect "99: a DELETE that fails is exit 1" "${RC}" "1"
has "99: and it says to delete it by hand" "The account example_use_a1 could not be deleted (HTTP 500): delete it by hand."
has "99: it still cleans up" "Cleaned up."
STUB_STATUS_HEAD=404 STUB_STATUS_DELETE=404 run 99.cleanup_DELETE.sh
expect "99: run again with nothing there it is exit 0 (it can be run twice)" "${RC}" "0"
rm -f "${UC}/session.cookie.jar" "${UC}/state.local.csrf"
OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 STUB_STATUS_DELETE=404 STUB_STATUS_HEAD=404 STUB_COUNTER="${WORK}/ctr" bash ./99.cleanup_DELETE.sh 2>&1); RC=$?
expect "99: with no session it logs in, so it can run at any time (exit 0)" "${RC}" "0"
run 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 00 run_all ==="
STUB_STATUS_GET_SEQ="200 500" STUB_STATUS_HEAD=404 STUB_STATUS_DELETE=404 GET_BODY="$(body err500b '{"message":"boom"}')" run 00.run_all.sh
expect "00: a failing step is exit 1" "${RC}" "1"
has "00: says which step failed" "01.settings_GET failed."
hasnt "00: and does not go on" "=== 02.activeUsers_GET ==="
has "00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="
expect "00: the cleanup tries the six accounts and the three units" "$(calls | grep -c '^DELETE .*\(accounts\|businessUnits\)/example_use_')" "9"
run 00.run_all.sh 0
expect "00: a wrong DAYS is exit 2 at once, nothing sent, no cleanup" "${RC}:$(ncalls)" "2:0"
has "00: with the usage" "Usage: ./00.run_all.sh [DAYS]"
run 00.run_all.sh 1 2
expect "00: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"
STEPS=$(sed -nE 's/^ *(for step in )?"([0-9][0-9]\.[A-Za-z_]+)[ "].*/\2/p; s/^ +"([0-9][0-9]\.[A-Za-z_]+)[ "].*/\1/p' "${UC_ROOT}/07-usage-reporting/00.run_all.sh" | tr '\n' ' ')
expect "00: the steps, in order, with the second part after the first" "$(grep -o '"[0-9][0-9]\.[A-Za-z_]*' "${UC_ROOT}/07-usage-reporting/00.run_all.sh" | tr -d '"' | tr '\n' ' ')" \
  "01.settings_GET 02.activeUsers_GET 03.generateReport_GET 04.transfers_billable_count_GET 05.report_vs_log 06.business_units_POST 07.transfers_make_POST 08.global_total_GET 09.business_unit_accounts_GET 10.usage_per_business_unit_GET 10.usage_per_business_unit_GET 10.usage_per_business_unit_GET 11.usage_all_business_units_GET "
expect "00: DAYS is given to steps 04 and 05, and the three units are asked of step 10" "$(grep -c '04.transfers_billable_count_GET ${DAYS}\|05.report_vs_log ${DAYS}' "${UC_ROOT}/07-usage-reporting/00.run_all.sh")" "1"

echo "=== The scripts: 'Copied from', executable, usage, the README ==="
for s in "${UC_ROOT}"/07-usage-reporting/[0-9][0-9].*.sh; do
    n="$(basename "${s}")"
    [ -x "${s}" ] && pass "${n}: is executable" || fail "${n}: is not executable"
    case "${n}" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin\/API 2\.0\/bash\/|EndUser\/API 2\.0\/bash\/|EndUser\/UseCases\/)[^ ,;()]+\.sh).*/\1/p' "${s}" | head -1)
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done
for s in "${UC_ROOT}"/07-usage-reporting/[0-9][0-9].*.sh; do
    n="$(basename "${s}")"
    grep -q "\`${n%.sh}" "${UC_ROOT}/07-usage-reporting/README.md" && pass "README: describes ${n}" || fail "README: does not name ${n}"
done

echo "=== The functions of the use case, and what the README promises ==="
MIDNIGHTS=$(cd "${UC}" && bash -c 'source ./lib.sh >/dev/null 2>&1; for N in 4 3 2 1 0 -1; do uc_midnight "$N"; done')
expect "uc_midnight gives six midnights with an RFC 2822 offset" "$(printf '%s\n' "${MIDNIGHTS}" | grep -c '^[A-Z][a-z][a-z], [0-9][0-9] [A-Z][a-z][a-z] [0-9]\{4\} 00:00:00 [+-][0-9]\{4\}$')" "6"
expect "uc_midnight 0 is today's midnight and 1 is the day before (the date part)" "$(printf '%s\n' "${MIDNIGHTS}" | sed -n 5p | cut -c6-16)" "$(date '+%d %b %Y')"
DAYS_AGO=$(cd "${UC}" && bash -c 'source ./lib.sh >/dev/null 2>&1; echo "$(uc_ddmmyyyy_ago 0) $(uc_ddmmyyyy_ago 1)"')
expect "uc_ddmmyyyy_ago gives today and yesterday as dd/MM/yyyy" "${DAYS_AGO}" "$(date +%d/%m/%Y) $(date -v-1d +%d/%m/%Y 2>/dev/null || date -d yesterday +%d/%m/%Y)"
SECONDS_AGO=$(cd "${UC}" && bash -c 'source ./lib.sh >/dev/null 2>&1; uc_rfc_seconds_ago 2')
expect "uc_rfc_seconds_ago gives an RFC 2822 time with an offset" "$(printf '%s\n' "${SECONDS_AGO}" | grep -c '^[A-Z][a-z][a-z], [0-9][0-9] [A-Z][a-z][a-z] [0-9]\{4\} [0-9:]\{8\} [+-][0-9]\{4\}$')" "1"
# the day of a clock change: with the time zone of Sofia the 25 October 2026 has 25 hours, and the midnights of the 25th and the 26th have two offsets (+0300 and +0200)
OFFSETS=$(TZ=Europe/Sofia bash -c 'if date -v-1d >/dev/null 2>&1; then date -j -f "%Y-%m-%d %H:%M:%S" "2026-10-25 00:00:00" +%z; date -j -f "%Y-%m-%d %H:%M:%S" "2026-10-26 00:00:00" +%z; else date -d "2026-10-25 00:00:00" +%z; date -d "2026-10-26 00:00:00" +%z; fi' | tr '\n' ' ')
expect "in the time zone of Sofia the midnights of 25 and 26 October 2026 have the offsets +0300 and +0200 (so a day is not 86400 seconds)" "${OFFSETS}" "+0300 +0200 "

README_FILE="${UC_ROOT}/07-usage-reporting/README.md"
python3 - "${README_FILE}" <<'PY' && pass "README: the python function turns a report into rows, the numbers of its tables hold" || fail "README: the python function or its numbers"
import re
import sys
text = open(sys.argv[1], encoding="utf-8").read()
code = re.search(r"```python\n(def report_rows.*?)```", text, re.S).group(1)
ns = {}
exec(compile(code, "readme", "exec"), ns)
sample = {"report": {"2026-10-26T00:00:00.000+02:00": {"usage": {"ST.Transfers": 88, "ST.TransfersIn": 80, "ST.TransfersOut": 30}},
                     "2026-10-25T00:00:00.000+03:00": {"usage": {"ST.Transfers": 1282, "ST.TransfersIn": 774, "ST.TransfersOut": 1089}}}}
assert ns["report_rows"](sample) == [("2026-10-25", 1282, 774, 1089), ("2026-10-26", 88, 80, 30)], ns["report_rows"](sample)
assert "1370" in text and 1282 + 88 == 1370 and 774 + 80 == 854 and 1089 + 30 == 1119
rows = re.findall(r"\| (\d+ Oct[^|]*) \| (\d+) / (\d+) / (\d+) \| (\d+) / (\d+) / (\d+) \| (\d+) \|", text)
assert len(rows) == 7, len(rows)
assert all(abs(int(r[1]) - int(r[4])) <= 10 and int(r[4]) == int(r[5]) + int(r[7]) for r in rows), rows
PY
python3 - "${README_FILE}" <<'PY' && pass "README: the sections, the two parts, and the statements the lab showed are there" || fail "README: a section or a statement is missing"
import sys
text = open(sys.argv[1], encoding="utf-8").read()
for heading in ("## The two parts", "## The three resources, and what each counts", "## Part 1: the whole server", "## Part 2: usage per business unit", "## What to check", "## What was not checked", "## Tests"):
    assert heading in text, heading
assert text.index("## Part 1: the whole server") < text.index("## Part 2: usage per business unit")
for needle in ("kept by name, not by account", "A deleted account stays in the list", "come from the product owner", "One page is 100 names", "with no offset",
               "named by the start of its day in the server's time zone, with the offset", "the end date is **included**", "Incorrect date frame", "The number of **billable** transfers of the day",
               "Not rebuilt", "A report you generate by hand includes today", "Read `resultSet.totalCount`", "`accountName=` is **not** a filter", "`isBillable` has three values",
               "A **decompress** step keeps the chain", "contains\" match", "`*` is **not** a wildcard", "businessUnit=example_use_bu1&isBillable=true",
               "**Yes: `businessUnit=NAME`**", "is ignored without a word", "Cannot find business unit with name nosuch.", "in no business unit",
               "The units do not add up to the report's total unless every account is in a unit", "Features/audit-billable-transfers"):
    assert needle in text, needle
assert "(../../../Features/Guidance/time-formats.md)" in text
PY
echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_07: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_07: PASS"
