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
          STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 bash "$@" 2>&1)
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
gets | head -n 1 | grep -qE "protocol=pesit&direction=Incoming&status=Processed&endTimeAfter=.*&endTimeBefore=.*&fields=coreId,pesitAckStatus$" \
    && pass "it lists the processed PeSIT inbounds in the window" || fail "list query: $(gets | head -n 1)"
expect "it acknowledges only the unacknowledged transfer whose outbound is there, even after one that is not ready" \
  "$(posts)" "${BASE}/logs/transfers/in-out/operations?operation=ack"
expect "it never looks at a transfer that is already acknowledged" "$(gets | grep -c CORE_DONE)" "0"
ls "${WORK}"/iterate_logs/acks/*/COREID_CORE_OUT.log >/dev/null 2>&1 \
    && pass "Acknowledgment.sh writes its log under the ROOT_FOLDER given to IteratePesitInbounds.sh" \
    || fail "no COREID_CORE_OUT.log under the ROOT_FOLDER given"

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

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_pesit_ack: PASS"
else
    echo "test_bash_pesit_ack: FAIL"
fi
exit "${FAILED}"
