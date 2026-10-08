#!/bin/bash
# ==============================================================================
# Run the 90.EndToEndAcknowledgment examples against a stub curl, and check
# which PeSIT transfers they acknowledge, and how.
#
# Acknowledgment.sh looks up the inbound transfer and its outbound transfers by
# coreId, then sends an ACK when the outbound is there, or a NACK (or nothing,
# exit 2) when it is not. IteratePesitInbounds.sh does that for every
# unacknowledged PeSIT inbound in a time window. The stub answers the inbound and
# the outbound lookups differently (STUB_CURL_GET_RULES), so each branch runs.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"

WORK="${TESTS_DIR}/output/bash_pesit_ack"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin" "${WORK}/elsewhere" "${WORK}/logs"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
cp -R "${REPO}/Admin/API 2.0/bash/90.EndToEndAcknowledgment" "${WORK}/admin/"
ACK_DIR="${WORK}/admin/90.EndToEndAcknowledgment"
BASE="https://st.example.com:8444/api/v2.0"

# The answers, one key per line, as the server sends them: the scripts read
# returnCount and the self link line by line
inbound() {  # inbound ID HOST
    cat <<JSON
{
  "resultSet" : {
    "returnCount" : 1
  },
  "result" : [ {
    "id" : "$1",
    "metadata" : {
      "links" : {
        "self" : "https://$2:8444/api/v2.0/logs/transfers/$1"
      }
    }
  } ]
}
JSON
}
outbound() {  # outbound COUNT
    printf '{\n  "resultSet" : {\n    "returnCount" : %s\n  },\n  "result" : [ ]\n}\n' "$1"
}
inbound in-1 st.example.com > "${WORK}/inbound.json"
inbound in-1 stack.example.com > "${WORK}/inbound_ack_host.json"
outbound 0 > "${WORK}/outbound_0.json"
outbound 1 > "${WORK}/outbound_1.json"

# rules TEXT FILE [TEXT FILE...]: a STUB_CURL_GET_RULES file
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}

# run DIR SCRIPT ARGS...: runs a script from DIR with the stub, using RULES
run() {
    local dir="$1"; shift
    OUT=$(cd "${dir}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_RULES="${RULES}" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE=1 bash "$@" 2>&1)
    RC=$?
}
posts() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); if (m == "POST") print}'; }
gets() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); if (m == "GET") print}'; }

echo "=== Acknowledgment.sh ==="

RULES=$(rules "incoming=true" "${WORK}/inbound.json" "direction=Outgoing" "${WORK}/outbound_1.json")
run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs"
expect "an outbound is there: it sends an ACK to the inbound transfer" \
  "${RC}:$(posts)" "0:${BASE}/logs/transfers/in-1/operations?operation=ack"
# curl's -w output ends without a newline, so HTTPC=200 is a last line with none
LOG=$(cat "${WORK}"/logs/acks/*/COREID_CORE1.log 2>/dev/null)
[[ "${LOG}" == *"ACK/NACK sent successfully"* ]] && [[ "${LOG}" != *"failed - HTTPC"* ]] \
    && pass "it reads the HTTP code on the last line of the answer, and logs the ACK as sent" \
    || fail "an ACK answered 200 is logged as failed: $(printf '%s\n' "${LOG}" | grep -E 'Attempt|sent' | tail -n 2)"
expect "it looked up the inbound, then the outbound, by coreId" "$(gets)" \
"${BASE}/logs/transfers?protocol=pesit&incoming=true&status=Processed&coreId=CORE1
${BASE}/logs/transfers?direction=Outgoing&status=Processed&coreId=CORE1"

RULES=$(rules "incoming=true" "${WORK}/inbound.json" "direction=Outgoing" "${WORK}/outbound_0.json")
run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs"
expect "no outbound, NACK allowed: it sends a NACK" "${RC}:$(posts)" "0:${BASE}/logs/transfers/in-1/operations?operation=nack"

run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 FALSE "${WORK}/logs"
expect "no outbound, NACK not allowed: it sends nothing, and exits 2 to be retried" "${RC}:$(posts)" "2:"

RULES=$(rules "incoming=true" "${WORK}/inbound_ack_host.json" "direction=Outgoing" "${WORK}/outbound_0.json")
run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs"
expect "a NACK only changes operation=ack, not an 'ack' elsewhere in the link" \
  "$(posts)" "https://stack.example.com:8444/api/v2.0/logs/transfers/in-1/operations?operation=nack"

RULES=$(rules "incoming=true" "${WORK}/inbound.json" "direction=Outgoing" "${WORK}/outbound_1.json")
run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com PUSH 1 TRUE "${WORK}/logs"
gets | grep -qF "direction=Outgoing&serverInitiated=true&status=Processed&coreId=CORE1" \
    && pass "PUSH counts only the outbound transfers the server started" || fail "PUSH query: $(gets)"

run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 2 TRUE "${WORK}/logs"
expect "two outbounds expected, one there: a NACK" "$(posts)" "${BASE}/logs/transfers/in-1/operations?operation=nack"

STATUS=500 STATUS_GET=200 run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs" FALSE 2 0
expect "every ACK attempt refused: it tries twice, then exits 1 (it used to exit 0 with the ACK never sent)" \
  "${RC}:$(posts | wc -l | tr -d ' ')" "1:2"
grep -q "attempt(s) to send the ACK failed" "${WORK}"/logs/acks/*/COREID_CORE1.log \
    && pass "and logs that every attempt failed" || fail "no 'attempt(s) to send the ACK failed' in the log"
STATUS=422 STATUS_GET=200 run "${ACK_DIR}" ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs" FALSE 3 0
expect "422, already acknowledged: one try, exit 0" "${RC}:$(posts | wc -l | tr -d ' ')" "0:1"

# a curl that cannot connect exits non-zero: that is a failed attempt, and the next one is made
mkdir -p "${WORK}/bin_fail"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = POST ] && exit 7; done\nexec "%s/bin/curl" "$@"\n' "${WORK}" > "${WORK}/bin_fail/curl"
chmod +x "${WORK}/bin_fail/curl"
OUT=$(cd "${ACK_DIR}" && PATH="${WORK}/bin_fail:${WORK}/bin:${PATH}" STUB_CURL_GET_RULES="${RULES}" STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 \
      bash ./Acknowledgment.sh CORE1 st.example.com MIX 1 TRUE "${WORK}/logs" FALSE 3 0 2>&1)
RC=$?
ATTEMPTS=$(cat "${WORK}"/logs/acks/*/COREID_CORE1.log | grep -c 'Retry count: 3')
expect "a curl that cannot connect exits 1, after all three attempts (set -e used to end it at the first)" "${RC}:${ATTEMPTS}" "1:1"

echo
echo "=== IteratePesitInbounds.sh ==="

cat > "${WORK}/list.json" <<'JSON'
{
  "result" : [
    { "coreId" : "CORE_NO_OUT", "pesitAckStatus" : null },
    { "coreId" : "CORE_OUT", "pesitAckStatus" : null },
    { "coreId" : "CORE_DONE", "pesitAckStatus" : "ack" }
  ]
}
JSON
inbound in-no st.example.com > "${WORK}/inbound_no.json"
inbound in-out st.example.com > "${WORK}/inbound_out.json"
RULES=$(rules "fields=coreId,pesitAckStatus" "${WORK}/list.json" \
              "incoming=true&status=Processed&coreId=CORE_NO_OUT" "${WORK}/inbound_no.json" \
              "incoming=true&status=Processed&coreId=CORE_OUT" "${WORK}/inbound_out.json" \
              "direction=Outgoing&status=Processed&coreId=CORE_NO_OUT" "${WORK}/outbound_0.json" \
              "direction=Outgoing&status=Processed&coreId=CORE_OUT" "${WORK}/outbound_1.json")
rm -rf "${WORK}/iterate_logs"
run "${WORK}/elsewhere" "${ACK_DIR}/IteratePesitInbounds.sh" 2 0 st.example.com "${WORK}/iterate_logs"
expect "run from another folder, it finds Acknowledgment.sh and exits 0" "${RC}" "0"
gets | head -n 1 | grep -qE "protocol=pesit&direction=Incoming&status=Processed&endTimeAfter=.*&endTimeBefore=.*&fields=coreId,pesitAckStatus&sortByStartTime=ascending&limit=100&offset=0$" \
    && pass "it lists the processed PeSIT inbounds in the window" || fail "list query: $(gets | head -n 1)"
expect "it acknowledges only the unacknowledged transfer whose outbound is there, even after one that is not ready" \
  "$(posts)" "${BASE}/logs/transfers/in-out/operations?operation=ack"
expect "it never looks at a transfer that is already acknowledged" "$(gets | grep -c CORE_DONE)" "0"
ls "${WORK}"/iterate_logs/acks/*/COREID_CORE_OUT.log >/dev/null 2>&1 \
    && pass "Acknowledgment.sh writes its log under the ROOT_FOLDER given to IteratePesitInbounds.sh" \
    || fail "no COREID_CORE_OUT.log under the ROOT_FOLDER given"

# more than one page: a full page of 100, all acknowledged, then a short one with a transfer to acknowledge
jq -n '{result: [range(0;100) | {coreId: ("DONE_\(.)"), pesitAckStatus: "ack"}]}' > "${WORK}/page1.json"
printf '{"result":[{"coreId":"CORE_OUT","pesitAckStatus":null}]}\n' > "${WORK}/page2.json"
RULES=$(rules "offset=100" "${WORK}/page2.json" "offset=0" "${WORK}/page1.json" \
              "incoming=true&status=Processed&coreId=CORE_OUT" "${WORK}/inbound_out.json" \
              "direction=Outgoing&status=Processed&coreId=CORE_OUT" "${WORK}/outbound_1.json")
run "${WORK}/elsewhere" "${ACK_DIR}/IteratePesitInbounds.sh" 2 0 st.example.com "${WORK}/iterate_logs_pages"
expect "a full first page: it reads the next one (offset 100) too, and acknowledges what is on it" \
  "${RC}:$(gets | grep -c 'direction=Incoming'):$(gets | grep -c 'offset=100'):$(posts)" "0:2:1:${BASE}/logs/transfers/in-out/operations?operation=ack"
expect "the pages are asked oldest first, so that they do not move" "$(gets | grep 'direction=Incoming' | grep -c 'sortByStartTime=ascending&limit=100')" "2"

# one transfer cannot be acknowledged: the other still is, and the exit status says so
printf '{"result":[{"coreId":"CORE_BAD","pesitAckStatus":null},{"coreId":"CORE_OUT","pesitAckStatus":null}]}\n' > "${WORK}/list_bad.json"
RULES=$(rules "fields=coreId,pesitAckStatus" "${WORK}/list_bad.json" \
              "incoming=true&status=Processed&coreId=CORE_BAD" "${WORK}/outbound_0.json" \
              "incoming=true&status=Processed&coreId=CORE_OUT" "${WORK}/inbound_out.json" \
              "direction=Outgoing&status=Processed&coreId=CORE_OUT" "${WORK}/outbound_1.json")
rm -rf "${WORK}/iterate_logs_bad"
run "${WORK}/elsewhere" "${ACK_DIR}/IteratePesitInbounds.sh" 2 0 st.example.com "${WORK}/iterate_logs_bad"
expect "one transfer fails: the other is still acknowledged, and it exits 1 (it used to exit 0)" \
  "${RC}:$(posts)" "1:${BASE}/logs/transfers/in-out/operations?operation=ack"

# the API output files: kept, or all removed when asked
files_left() { find "$1" -path '*/API/*.txt' 2>/dev/null | wc -l | tr -d ' '; }
expect "the API output files are kept by default" "$([ "$(files_left "${WORK}/iterate_logs_bad")" -gt 0 ] && echo kept || echo none)" "kept"
rm -rf "${WORK}/iterate_logs_clear"
run "${WORK}/elsewhere" "${ACK_DIR}/IteratePesitInbounds.sh" 2 0 st.example.com "${WORK}/iterate_logs_clear" TRUE
expect "with CLEAR_API_OUTPUT_FILES=TRUE none is left, not just the last Core ID's" "$(files_left "${WORK}/iterate_logs_clear")" "0"

echo
echo "=== The bat twins, read as text (they cannot run here) ==="

BAT_DIR="${REPO}/Admin/API 2.0/bat/90.EndToEndAcknowledgment"
ACK_BAT=$(grep -v '^REM' "${BAT_DIR}/Acknowledgment.bat")
ITER_BAT=$(grep -v '^REM' "${BAT_DIR}/IteratePesitInbounds.bat")
! printf '%s\n' "${ACK_BAT}" | grep -F 'findstr "self"' | grep -qF 'delims=:' \
    && pass "Acknowledgment.bat does not split the self link on ':' (it holds https://host:port)" \
    || fail "Acknowledgment.bat splits the self link on ':', which keeps only \"https"
[[ "${ACK_BAT}" != *':ack=nack%'* ]] && [[ "${ACK_BAT}" == *'operation=nack'* ]] \
    && pass "Acknowledgment.bat builds the NACK link from the operation, not by replacing every 'ack'" \
    || fail "Acknowledgment.bat still replaces every 'ack' in the link"
[ "$(printf '%s\n' "${ACK_BAT}" | grep -cE '^SET [A-Z_]+=%[1-9]$')" -eq 0 ] \
    && pass "Acknowledgment.bat strips the quotes from its arguments (%~N)" \
    || fail "Acknowledgment.bat keeps the quotes a caller put around an argument"
[[ "${ITER_BAT}" == *'Acknowledgment.bat" %%C "%HOST%" MIX 1 FALSE "%ROOT_FOLDER%"'* ]] \
    && pass "IteratePesitInbounds.bat passes its ROOT_FOLDER on" || fail "IteratePesitInbounds.bat does not pass its ROOT_FOLDER on"
[[ "${ITER_BAT}" != *"ToString(''"* ]] \
    && pass "IteratePesitInbounds.bat quotes its date format once, as PowerShell needs" \
    || fail "IteratePesitInbounds.bat wraps its date format in '' '', which PowerShell reads as an empty string"


# These cannot run here: each line below is a cmd.exe or PowerShell rule, checked in the text
[[ "${ACK_BAT}" != *'SET OUTBOUND_TYPE_REQUEST=direction=Outgoing&'* ]] \
    && [[ "${ACK_BAT}" == *'SET "OUTBOUND_TYPE_REQUEST=direction=Outgoing&serverInitiated=true"'* ]] \
    && pass "Acknowledgment.bat quotes the SET of a query with & (an unquoted & ends the SET, and PUSH and DOWNLOAD lose serverInitiated)" \
    || fail "Acknowledgment.bat sets OUTBOUND_TYPE_REQUEST with an unquoted &"
[[ "${ACK_BAT}" == *'SET "url=%~2"'* ]] && [[ "${ACK_BAT}" != *'SET url=%2'* ]] \
    && pass "Acknowledgment.bat drops the quotes of the URL it is given, so the one pair it adds keeps the & inside" \
    || fail "Acknowledgment.bat keeps the quotes of the URL, which doubles them and leaves the & outside"
! printf '%s\n%s\n' "${ACK_BAT}" "${ITER_BAT}" | grep -qE 'Get-Date -Format [A-Za-z]|Get-Date -Format '"''" \
    && pass "the bat scripts quote the Get-Date format once, with single quotes (PowerShell takes an unquoted one for two arguments)" \
    || fail "a bat script has an unquoted or double-quoted Get-Date format"
[[ "${ACK_BAT}" == *'findstr /B "HTTPC="'* ]] && [[ "${ACK_BAT}" != *'IN ("%ACK_NACK_OUTPUT%")'* ]] \
    && pass "Acknowledgment.bat reads only the HTTPC= line of the answer (it logged a warning and slept for every line of the body)" \
    || fail "Acknowledgment.bat walks every line of the answer"
[[ "${ACK_BAT}" == *'IF "%ACK_RESULT%"=="FAILED"'* ]] && [[ "${ACK_BAT}" == *'EXIT /B %EXIT_CODE_ERROR%'* ]] \
    && pass "Acknowledgment.bat exits 1 when every attempt failed" || fail "Acknowledgment.bat always exits 0"
[ "$(printf '%s\n' "${ACK_BAT}" | grep -c 'IF ERRORLEVEL 1 EXIT /B %EXIT_CODE_ERROR%')" -eq 2 ] \
    && pass "Acknowledgment.bat stops when a lookup is refused, as the bash version does" \
    || fail "Acknowledgment.bat carries on after a refused lookup"
[[ "${ITER_BAT}" == *'offset=%OFFSET%'* ]] && [[ "${ITER_BAT}" == *'sortByStartTime=ascending&limit=%PAGE_SIZE%'* ]] && [[ "${ITER_BAT}" == *'GOTO :next_page'* ]] \
    && pass "IteratePesitInbounds.bat reads the log page by page, oldest first" \
    || fail "IteratePesitInbounds.bat reads only the first page of the log"
[[ "${ITER_BAT}" == *'SET ACK_RC=!ERRORLEVEL!'* ]] && [[ "${ITER_BAT}" == *'SET /A FAILED+=1'* ]] && [[ "${ITER_BAT}" == *'IF %FAILED% GTR 0'* ]] \
    && pass "IteratePesitInbounds.bat counts the transfers Acknowledgment.bat failed on, and exits 1" \
    || fail "IteratePesitInbounds.bat ignores what Acknowledgment.bat returns"
echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_pesit_ack: PASS"
else
    echo "test_bash_pesit_ack: FAIL"
fi
exit "${FAILED}"
