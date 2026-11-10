#!/bin/bash
# ==============================================================================
# Run Admin/UseCases/10-qlt-events-generation against a stub curl, and check the calls each script makes: the method, the URL, the body of a POST, PATCH or PUT (the Sentinel settings, the options of
# the Fusion integration, the objects of a scenario), the credentials (a session for the Admin API, Basic for the End User API), the headers, what it prints, and its exit code. The overflow files the
# stub serves are made here: a circular buffer header, events (XFBTransfer, XFBRouting, CycleLink and AUDIT) each after a length and a colon, with the three kinds of separator the real file has,
# and padding. The fake HTTP server is stood in for by a process whose command names it; the requests it is sent are stood in for by a `sleep` that logs one each time.
#
# Top level: 01 the account, 02 the copy of the settings, 03 the patch (every state on, a slash in a name, a state the server does not list, the reads file), 04 the fake server, 99 everything put back.
# Each scenario (1-upload-push, 2-upload-fusion-partner): 01 the objects (one step or two, the Fusion integration), 02 the flow (the overflow file turned to the case file and away again, in every
# outcome), 03 the events and the requests, 04 the ties to the transfer log, 99 the objects deleted and the Fusion options compared. 00 failing fast and still cleaning up; the README against the folder.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_10"
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
# a sleep that does not wait, and that stands for the time in which the fake server is sent a request: it logs one each time it is called (FAKE_SLEEP_ADDS=0: none)
cat > "${WORK}/bin/sleep" <<'SLEEP'
#!/bin/bash
if [ "${FAKE_SLEEP_ADDS:-1}" = "1" ] && [ -n "${FAKE_LOG}" ]; then
    echo '{"t":"07:00:00","method":"PUT","path":"/upload","bytes":300,"contentType":"multipart/form-data","file":"x.txt","answer":200}' >> "${FAKE_LOG}"
fi
exit 0
SLEEP
chmod +x "${WORK}/bin/sleep"
# the uploaded file is named with the time: a date that says the same second each time makes the names the fixtures have
cat > "${WORK}/bin/date" <<'DATE'
#!/bin/bash
if [ "$1" = "+%s" ]; then echo 1700000000; else exec /bin/date "$@"; fi
DATE
chmod +x "${WORK}/bin/date"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/10-qlt-events-generation" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
EU="https://st.example.com:8443/api/v2.0"
UC="${WORK}/tree/UseCases/10-qlt-events-generation"
S1="${UC}/1-upload-push"
S2="${UC}/2-upload-fusion-partner"
README_FILE="${UC_ROOT}/10-qlt-events-generation/README.md"
FAKE_LOG="${UC}/state.local.fake_server.log"
WINDOW="Tue, 10 Nov 2026 07:52:08 +0200"
PW="Ex1!abc123"
UPLOAD1="push_1700000000.txt"
UPLOAD2="fusion_1700000000.txt"
DECOY_PID=""
clean_all() { rm -f "${UC}"/state.local.* "${UC}/session.cookie.jar" "${S1}"/state.local.* "${S2}"/state.local.*; }
clean_all
trap '[ -z "${DECOY_PID}" ] || kill "${DECOY_PID}" 2>/dev/null; for p in $(cat "${UC}/state.local.fake_server.pid" 2>/dev/null); do ps -o command= -p "$p" 2>/dev/null | grep -q "fake_http_server.py" && kill "$p"; done' EXIT

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
rules() {
    local out="${WORK}/rules_${RANDOM}${RANDOM}.tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
reset_counters() { rm -f "${WORK}"/ctr.*; }

# --- the overflow files the stub serves ------------------------------------------------------------------------------------------------------------------
# an event is framed as in the file: a separator, nine digits of length, a colon, the XML. The separator is XSEP: a line break unless it is set (the real file has a line break before most records, a
# carriage return before the first and nothing before some). One attribute of each XFBTransfer has no value.
frame() { printf '%b%09d:%s' "${XSEP-\\n}" "${#1}" "$1"; }
HDR='<?xml version="1.0" encoding="UTF-8"?><TrkDescriptor><TrkXML VERSION="1.0"/><TrkObject>'
FTR='</TrkObject></TrkDescriptor>'
# xfb STATE FILE TIME DIR CORE LOCAL SIZE [FILENAME]
xfb() { frame "${HDR}<TrkIdentifier TYPE=\"Event\" NAME=\"XFBTransfer\" VERSION=\"1.0\"/><TrkAttr name=\"EVENTTIME\" val=\"$3\"/><TrkAttr name=\"STATE\" val=\"$1\"/><TrkAttr name=\"TLSVERSION\"/><TrkAttr name=\"DIRECTION\" val=\"$4\"/><TrkAttr name=\"COREID\" val=\"$5\"/><TrkAttr name=\"LOCALID\" val=\"$6\"/><TrkAttr name=\"FILESIZE\" val=\"$7\"/><TrkAttr name=\"PROTOCOLFILENAME\" val=\"$2\"/><TrkAttr name=\"FILENAME\" val=\"${8:-/home/example_qlt/$2}\"/>${FTR}"; }
routing() { frame "${HDR}<TrkIdentifier TYPE=\"Event\" NAME=\"XFBRouting\" VERSION=\"1.0\"/><TrkAttr name=\"EVENTTIME\" val=\"$1\"/><TrkAttr name=\"STATE\" val=\"POST_PROC\"/>${FTR}"; }
audit() { frame "${HDR}<TrkIdentifier TYPE=\"Event\" NAME=\"AUDIT\" VERSION=\"1.0\"/><TrkAttr name=\"EVENTTIME\" val=\"$2\"/><TrkAttr name=\"ACTION\" val=\"$1\"/><TrkAttr name=\"LOGINNAME\" val=\"example_qlt\"/>${FTR}"; }
# a CycleLink has a lowercase type and no name
link() { frame '<?xml version="1.0" encoding="ISO-8859-1"?><TrkDescriptor><TrkXML version="1.0"/><TrkObject><TrkIdentifier type="CycleLink"/><TrkAttr name="EVENTTIME" val="'"$1"'"/><TrkAttr name="PARENTOBJECT" val="XFBTransfer"/><TrkAttr name="PARENTCYCLEID" val="XFyucTJ8tQxv"/><TrkAttr name="CHILDOBJECT" val="'"$2"'"/><TrkAttr name="CHILDCYCLEID" val="XFrgHgs2dbvn"/>'"${FTR}"; }
head_frame() { printf '%s' "000000000000000:000000000001000:000000000001000:000000000000009:Circular buffer file version 3.40.0-1"; printf '%*s' 300 ''; }
tail_frame() { printf '%s' "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; }
# push_case NAME KIND: KIND is full, no_sent (SENT is not there) or empty
push_case() {
    local out="${WORK}/$1.dat"
    {
        head_frame
        if [ "$2" != "empty" ]; then
            XSEP='\r' audit LOGIN_START 07:52:33; audit LOGIN_END 07:52:33
            xfb RECEIVING "${UPLOAD1}" 07:52:33 R core-1 local-up ""
            xfb POST_PROC/ARCHIVED "${UPLOAD1}" 07:52:34 R core-1 local-up 47 "/home/archives/20261110/example_qlt/example_qlt/${UPLOAD1}feed-1"
            xfb RECEIVED "${UPLOAD1}" 07:52:34 R core-1 local-up 47
            xfb POST_PROC "${UPLOAD1}" 07:52:35 "" core-1 "" 47
            xfb TO_EXECUTE "${UPLOAD1}" 07:52:35 S core-1 "" 47
            link 07:52:35 XFBTransfer
            xfb SENDING "${UPLOAD1}" 07:52:35 S core-1 "" 47
            [ "$2" = "no_sent" ] || XSEP="" xfb SENT "${UPLOAD1}" 07:52:36 S core-1 local-down 47       # no separator: it follows SENDING directly
            routing 07:52:36
            link 07:52:36 XFBRouting
            xfb POST_PROC "other.txt" 07:52:37 "" core-2 "" 47      # another flow of the server, in the case file too
        fi
        tail_frame
    } > "${out}"
    echo "${out}"
}
# fusion_case NAME KIND: KIND is full, no_final (the file Fusion sent back is not sent on) or empty
fusion_case() {
    local out="${WORK}/$1.dat" response="fusion_response_1700000001.dat"
    {
        head_frame
        if [ "$2" != "empty" ]; then
            XSEP='\r' audit LOGIN_START 07:54:29; audit LOGIN_END 07:54:29
            xfb RECEIVING "${UPLOAD2}" 07:54:29 R core-2 local-up ""
            xfb RECEIVED "${UPLOAD2}" 07:54:29 R core-2 local-up 47
            xfb SENDING "${UPLOAD2}" 07:54:31 S core-2 "" 47
            xfb RECEIVING "${response}" 07:54:31 R core-2 local-resp ""
            link 07:54:31 XFBTransfer
            xfb SENDING "${response}" 07:54:31 S core-2 "" 47
            [ "$2" = "no_final" ] || xfb SENT "${response}" 07:54:31 S core-2 local-out 47
            routing 07:54:31
            xfb SENT "${UPLOAD2}" 07:54:31 S core-2 local-fus 47
            xfb RECEIVED "${response}" 07:54:37 R core-2 local-resp 47        # the straggler: six seconds after the rest
            xfb POST_PROC "other.txt" 07:54:38 "" core-1 "" 47      # another flow of the server, in the case file too
        fi
        tail_frame
    } > "${out}"
    echo "${out}"
}
CASE1="$(push_case case1 full)"; CASE1_NOSENT="$(push_case case1_nosent no_sent)"; CASE_EMPTY="$(push_case case_empty empty)"
CASE2="$(fusion_case case2 full)"; CASE2_NOFINAL="$(fusion_case case2_nofinal no_final)"

SENTINEL="$(body sentinel '{"enabled":true,"host":"sentinel.example.com","port":1305,"useSecureConnection":false,"heartbeatEnabled":true,"heartbeatDelay":30,"overflowFilePath":"/var/tmp/overflow_real","overflowFileSize":5,"overflowFileThreshold":90,"overflowFilePolicy":"ignore","eventStates":{"RECEIVING":"true","RECEIVED":"required","SENDING":"true","SENT":"required","ACKED":"true","DELETED":"false","POST_PROC/ROUTED":"false","LOGIN_START (AUDIT)":"false"},"mappingRules":{}}')"
SENTINEL_ALL_ON="$(body sentinel_all_on "$(jq -c '.eventStates |= with_entries(.value |= (if . == "false" then "true" else . end))' "${SENTINEL}")")"
SENTINEL_OFF_LEFT="$(body sentinel_off_left "$(jq -c '.eventStates.DELETED = "false"' "${SENTINEL_ALL_ON}")")"
SENTINEL_BARE="$(body sentinel_bare '{"enabled":false,"host":"","port":1305,"heartbeatEnabled":false,"heartbeatDelay":10,"overflowFilePath":"","overflowFileSize":null,"overflowFileThreshold":null,"overflowFilePolicy":"ignore","eventStates":{"RECEIVING":"false","RECEIVED":"required","SENT":"required"},"mappingRules":{}}')"
SENTINEL_BARE_AFTER="$(body sentinel_bare_after '{"enabled":false,"host":"","port":1305,"heartbeatEnabled":false,"heartbeatDelay":10,"overflowFilePath":"","overflowFileSize":5,"overflowFileThreshold":90,"overflowFilePolicy":"ignore","eventStates":{"RECEIVING":"true","RECEIVED":"required","SENT":"required"},"mappingRules":{}}')"
SENTINEL_CHANGED="$(body sentinel_changed "$(jq -c '.host = "192.0.2.1"' "${SENTINEL}")")"
FUSION_OPTS="$(body fusion_opts '{"result":[{"name":"Fusion.Integrations.Registry","values":["myFusion"]},{"name":"Fusion.Integrations.Registry.myFusion.authType","values":["BASIC"]},{"name":"Fusion.Integrations.ConnectionTimeout","values":["30"]}]}')"
FUSION_OPTS_MOVED="$(body fusion_opts_moved '{"result":[{"name":"Fusion.Integrations.Registry","values":["myFusion","example_qlt_fusion"]},{"name":"Fusion.Integrations.Registry.myFusion.authType","values":["BASIC"]},{"name":"Fusion.Integrations.ConnectionTimeout","values":["30"]}]}')"
EVENTS_NONE="$(body events_none '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')"
EVENTS_STUCK="$(body events_stuck '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"id":"0xSTUCK1","status":"active"}]}')"
LOG1="$(body log1 '{"resultSet":{"returnCount":4,"totalCount":4},"result":[
  {"coreId":"core-1","id":{"mTransferStatusId":"local-down"},"status":"Processed","filename":"'"${UPLOAD1}"'"},
  {"coreId":"core-1","id":{"mTransferStatusId":"local-up"},"status":"Processed","filename":"'"${UPLOAD1}"'"},
  {"coreId":"core-8","id":{"mTransferStatusId":"local-8"},"status":"Processed","filename":"qlt_1_upload_push.dat"},
  {"coreId":"core-9","id":{"mTransferStatusId":"local-9"},"status":"Processed","filename":"qlt_reads.dat"}]}')"
LOG1_LOST="$(body log1_lost '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"coreId":"core-nowhere","id":{"mTransferStatusId":"local-nowhere"},"status":"Processed","filename":"'"${UPLOAD1}"'"}]}')"
LOG_ALL="$(body log_all '{"resultSet":{"returnCount":3,"totalCount":3},"result":[
  {"coreId":"core-1","id":{"mTransferStatusId":"local-up"},"status":"Processed","filename":"push_1700000000.txt"},
  {"coreId":"core-2","id":{"mTransferStatusId":"local-fus"},"status":"Processed","filename":"fusion_1700000000.txt"},
  {"coreId":"core-9","id":{"mTransferStatusId":"local-9"},"status":"Processed","filename":"qlt_reads.dat"}]}')"
LOG_NONE="$(body log_none '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')"
LOG2="$(body log2 '{"resultSet":{"returnCount":2,"totalCount":2},"result":[
  {"coreId":"core-2","id":{"mTransferStatusId":"local-fus"},"status":"Processed","filename":"'"${UPLOAD2}"'"},
  {"coreId":"core-2","id":{"mTransferStatusId":"local-out"},"status":"Processed","filename":"fusion_response_1700000001.dat"}]}')"
LISTING="$(body listing '{"files":[{"fileName":"qlt_1_upload_push.dat","isRegularFile":true,"isDirectory":false},{"fileName":"qlt_reads.dat","isRegularFile":true,"isDirectory":false},{"fileName":"qlt_push_in","isRegularFile":false,"isDirectory":true}]}')"
REQUESTS_1='{"t":"07:52:35","method":"PUT","path":"/upload","bytes":314,"contentType":"multipart/form-data","file":"'"${UPLOAD1}"'","answer":200}'
REQUESTS_2='{"t":"07:54:31","method":"POST","path":"/fusion","bytes":2677,"contentType":"multipart/form-data","file":"'"${UPLOAD2}"'","answer":200}
{"t":"07:54:31","method":"PUT","path":"/upload","bytes":330,"contentType":"multipart/form-data","file":"fusion_response_1700000001.dat","answer":200}'

# run DIRECTORY SCRIPT [PARAMS]: with a session jar in place. RULES, GET_BODY, POST_BODY and the *_STATUS variables set the answers.
run() {
    local dir="$1" rel="$2"; shift 2
    reset_counters
    touch "${UC}/session.cookie.jar"
    OUT=$(cd "${dir}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_GET_SEQUENCE="${GET_SEQDIR:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_COUNTER="${WORK}/ctr" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_STATUS_GET="${GET_STATUS:-200}" STUB_STATUS_POST="${POST_STATUS:-201}" STUB_STATUS_POST_SEQ="${POST_SEQ:-}" STUB_STATUS_GET_SEQ="${GET_SEQ:-}" STUB_STATUS_HEAD="${HEAD_STATUS:-404}" \
          STUB_STATUS_PUT="${PUT_STATUS:-204}" STUB_STATUS_PATCH="${PATCH_STATUS:-204}" STUB_STATUS_PATCH_SEQ="${PATCH_SEQ:-}" STUB_STATUS_DELETE="${DELETE_STATUS:-204}" STUB_LOCATION_PREFIX="${LOCATION_PREFIX:-ID}" \
          STUB_BODY_OTHER="${OTHER_BODY:-}" STUB_CURL_PRINT_CODE=1 ST_ENDUSER_PORT=8443 ST_CALLBACK_HOST="${CALLBACK-callback.example.com}" ST_CALLBACK_PORT="${CALLBACK_PORT:-18081}" \
          FAKE_LOG="${FAKE_LOG}" FAKE_SLEEP_ADDS="${SLEEP_ADDS:-1}" bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }      # without the check of the session that comes first (GET /myself)
ncalls() { calls | wc -l | tr -d ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
file_mode() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }
short() { ucalls | sed "s#${BASE}/##; s#${EU}/#EU:#" | tr '\n' ' '; }
short_all() { calls | sed "s#${BASE}/##; s#${EU}/#EU:#" | tr '\n' ' '; }      # for the steps that open no session
set_password() { printf '%s' "${PW}" > "${UC}/state.local.password"; }
set_copy() { cp "$1" "${UC}/state.local.sentinel.json"; }
start_decoy() { python3 -c 'import time; time.sleep(600)' fake_http_server.py & DECOY_PID=$!; disown "${DECOY_PID}" 2>/dev/null; printf '%s\n' "${DECOY_PID}" > "${UC}/state.local.fake_server.pid"; : > "${FAKE_LOG}"; }
stop_decoy() { [ -z "${DECOY_PID}" ] || kill "${DECOY_PID}" 2>/dev/null; DECOY_PID=""; rm -f "${UC}/state.local.fake_server.pid"; }
RULES_COMMON() { rules 'configurations/sentinel' "${SENTINEL_CHANGED}" 'configurations/options' "${FUSION_OPTS}" 'events' "${EVENTS_NONE}" "$@"; }

echo "=== 01 the account ==="
run "${UC}" 01.accounts_POST.sh
expect "01: exit 0, one HEAD then one POST to /accounts" "${RC}:$(ucalls | grep -c '^HEAD'):$(ucalls | grep -c "^POST ${BASE}/accounts$")" "0:1:1"
expect "01: the body: a user, its own home, its fixed ids, the user and a password" \
    "$(payload 1 | jq -c '[.name, .type, .homeFolder, .uid, .gid, .user.name, (.user.passwordCredentials.password | length > 8)]')" '["example_qlt","user","/home/example_qlt","41733","41733","example_qlt",true]'
expect "01: the password file holds it, and only its owner can read it" "$(cat "${UC}/state.local.password"):$(file_mode "${UC}/state.local.password")" "$(payload 1 | jq -r .user.passwordCredentials.password):600"
clean_all
HEAD_STATUS=200 run "${UC}" 01.accounts_POST.sh
expect "01: an account that is there is exit 1, and nothing is created" "${RC}:$(ucalls | grep -c '^POST'):$(test -e "${UC}/state.local.password" && echo file || echo none)" "1:0:none"
has "01: it names the account and the cleanup" "example_qlt exists already. Nothing was created. Remove it with 99.cleanup_DELETE.sh."
POST_STATUS=400 POST_BODY="$(body e1 '{"validationErrors":["name is taken"]}')" run "${UC}" 01.accounts_POST.sh
expect "01: a POST that is refused is exit 1, with the reason, and no password is kept" "${RC}:$(test -e "${UC}/state.local.password" && echo file || echo none)" "1:none"
has "01: the reason" "name is taken"
run "${UC}" 01.accounts_POST.sh now
expect "01: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
clean_all

echo "=== 02 the copy of the settings ==="
RULES="$(rules 'configurations/sentinel' "${SENTINEL}")" run "${UC}" 02.sentinel_GET.sh
expect "02: exit 0, one GET of /configurations/sentinel, kept as it was, private" "${RC}:$(ucalls | grep -c "^GET ${BASE}/configurations/sentinel$"):$(jq -S . "${UC}/state.local.sentinel.json" | md5sum | cut -c1-32 2>/dev/null || jq -S . "${UC}/state.local.sentinel.json" | md5):$(file_mode "${UC}/state.local.sentinel.json")" \
    "0:1:$(jq -S . "${SENTINEL}" | md5sum | cut -c1-32 2>/dev/null || jq -S . "${SENTINEL}" | md5):600"
has "02: it says where reports go" "reporting: on, to sentinel.example.com:1305"
has "02: how many states are reported" "transfer states reported: 5 of 8"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_BARE}")" run "${UC}" 02.sentinel_GET.sh
expect "02: a second run does not overwrite the copy, and does not read the settings again" "${RC}:$(jq -r .host "${UC}/state.local.sentinel.json"):$(ucalls | grep -c 'configurations/sentinel')" "0:sentinel.example.com:0"
clean_all
RULES="$(rules 'configurations/sentinel' "${SENTINEL_BARE}")" run "${UC}" 02.sentinel_GET.sh
has "02: a server with no host prints the dashes" "reporting: off, to -:1305"
clean_all
GET_STATUS=500 RULES="$(rules 'configurations/sentinel' "${WORK}/e1.json")" run "${UC}" 02.sentinel_GET.sh
expect "02: a refused read is exit 1, and no copy is kept" "${RC}:$(test -e "${UC}/state.local.sentinel.json" && echo file || echo none)" "1:none"
run "${UC}" 02.sentinel_GET.sh now
expect "02: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
clean_all

echo "=== 03 every event, to a Sentinel that cannot be reached ==="
run "${UC}" 03.sentinel_PATCH.sh
expect "03: no copy is exit 1, and nothing is sent" "${RC}:$(ncalls)" "1:0"
set_copy "${SENTINEL}"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_ALL_ON}")" run "${UC}" 03.sentinel_PATCH.sh
expect "03: exit 0, a PATCH of /configurations/sentinel, then the read" "${RC}:$(short)" "0:PATCH configurations/sentinel GET configurations/sentinel "
expect "03: the patch: the host, the port, the reads file in the home of the account, reporting on" "$(payload 1 | jq -c '[.[:4][] | [.op, .path, .value]]')" \
    '[["replace","/host","192.0.2.1"],["replace","/port",1305],["replace","/overflowFilePath","/home/example_qlt/qlt_reads.dat"],["replace","/enabled",true]]'
expect "03: no size or threshold is added when the copy has them" "$(payload 1 | jq -c '[.[] | select(.path | test("overflowFileSize|overflowFileThreshold"))] | length')" "0"
expect "03: the states that were off are turned on, a slash in a name is ~1: the three that were off and listed are replaced" \
    "$(payload 1 | jq -c '[.[] | select(.path | startswith("/eventStates/")) | select(.op == "replace")] | map([.path, .value])')" '[["/eventStates/DELETED","true"],["/eventStates/LOGIN_START (AUDIT)","true"],["/eventStates/POST_PROC~1ROUTED","true"]]'
expect "03: and the states the server does not list are added, all of the reference (37 names, 5 of them on): 32 in all, none twice" \
    "$(payload 1 | jq -c '[.[] | select(.path | startswith("/eventStates/"))] | [length, (map(.path) | unique | length), ([.[] | select(.op == "add")] | length)]')" "[32,32,29]"
expect "03: a state that is on or required is not touched" "$(payload 1 | jq -c '[.[] | select(.path == "/eventStates/RECEIVED" or .path == "/eventStates/SENDING")] | length')" "0"
has "03: it says how many it turned on" "turning on 32 state(s)"
has "03: the settings now" "states reported: 8 of 8, 2 of them required"
expect "03: with the csrfToken and the content type on the patch" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: csrfToken'):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: application/json')" "1:1"
set_copy "${SENTINEL_BARE}"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_ALL_ON}")" run "${UC}" 03.sentinel_PATCH.sh 127.0.0.1 9999
expect "03: a copy with no size and no threshold: they are added" "$(payload 1 | jq -c '[.[] | select(.path | test("overflowFile")) | [.op, .path, .value]]')" '[["replace","/overflowFilePath","/home/example_qlt/qlt_reads.dat"],["add","/overflowFileSize",5],["add","/overflowFileThreshold",90]]'
expect "03: and the host and the port are the ones given" "$(payload 1 | jq -c '[.[0].value, .[1].value]')" '["127.0.0.1",9999]'
set_copy "${SENTINEL}"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_OFF_LEFT}")" run "${UC}" 03.sentinel_PATCH.sh
expect "03: a state still off in the answer is exit 1" "${RC}" "1"
has "03: and is named" "still off: DELETED"
for bad in "a b c" "host 0" "host 65536" "host x"; do
    run "${UC}" 03.sentinel_PATCH.sh ${bad}
    expect "03: '${bad}' is exit 2 with the usage, and nothing is sent" "${RC}:$(ncalls)" "2:0"
done
PATCH_STATUS=400 OTHER_BODY="$(body e3 '{"validationErrors":["host must not be null or empty"]}')" run "${UC}" 03.sentinel_PATCH.sh
expect "03: a refused patch is exit 1, with the reason, and the settings are not read" "${RC}:$(ucalls | grep -c '^GET')" "1:0"
has "03: the reason" "host must not be null or empty"
clean_all

echo "=== 04 the fake HTTP server ==="
CALLBACK= run "${UC}" 04.fakeServer_start.sh
expect "04: no ST_CALLBACK_HOST is exit 1, and no server is started" "${RC}:$(test -e "${UC}/state.local.fake_server.pid" && echo pid || echo none)" "1:none"
has "04: it says what to set" "ST_CALLBACK_HOST is not set"
PORT_TEST=$((20000 + RANDOM % 20000))
CALLBACK_PORT="${PORT_TEST}" run "${UC}" 04.fakeServer_start.sh
expect "04: exit 0, a process is started and its id is kept" "${RC}:$(ps -o command= -p "$(cat "${UC}/state.local.fake_server.pid")" 2>/dev/null | grep -c "fake_http_server.py ${PORT_TEST} ")" "0:1"
has "04: it says where the server will be reached" "http://callback.example.com:${PORT_TEST}"
FIRST_PID="$(cat "${UC}/state.local.fake_server.pid")"
CALLBACK_PORT="${PORT_TEST}" run "${UC}" 04.fakeServer_start.sh
expect "04: a second run leaves it as it is: exit 0, the same process" "${RC}:$(cat "${UC}/state.local.fake_server.pid")" "0:${FIRST_PID}"
has "04: it says it runs already" "runs already"
kill "${FIRST_PID}" 2>/dev/null; rm -f "${UC}/state.local.fake_server.pid"
run "${UC}" 04.fakeServer_start.sh now
expect "04: a parameter is exit 2" "${RC}" "2"
clean_all

# --- the two scenarios ----------------------------------------------------------------------------------------------------------------------------------
scenario_tests() {
    local N="$1" DIR="$2" TAG="$3" FOLDER="$4" CASE="$5" STEPS="$6" REQS="$7" UPLOAD="$8" EVTFILE="$9" EVTBAD="${10}" LOGFILE="${11}" REQLINES="${12}"
    echo "=== scenario ${N}: ${DIR##*/} ==="
    set_password; set_copy "${SENTINEL}"
    # -- 01 the objects
    RULES="$(RULES_COMMON)" CALLBACK= run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: no ST_CALLBACK_HOST is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    rm -f "${UC}/state.local.password"
    RULES="$(RULES_COMMON)" run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: no password is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    set_password
    rm -f "${UC}/state.local.sentinel.json"
    RULES="$(RULES_COMMON)" run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: no copy of the settings is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    set_copy "${SENTINEL}"
    RULES="$(RULES_COMMON)" run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: exit 0" "${RC}" "0"
    local posts; posts="$(ucalls | grep '^POST' | sed "s#POST ${BASE}/##; s#POST ${EU}/#EU:#" | tr '\n' ' ')"
    expect "${N}/01: the POSTs: the site, the application, the subscription, three routes, then the folder of the account" "${posts}" "sites applications subscriptions routes routes routes EU:files/${FOLDER} "
    # the payloads of the Admin API come first in the output; with Fusion the two PUTs of the options are before them
    local off=0; [ "${N}" = 2 ] && off=2
    expect "${N}/01: the site is a Generic HTTP one to the fake server: PUT /upload on the callback host and port" \
        "$(payload $((off + 1)) | jq -c '[.type, .protocol, .name, .account, .ghttpHost, .ghttpPort, .ghttpUploadUrlPath, .ghttpUploadMethod, .ghttpNetworkZone]')" \
        "[\"http-generic\",\"http-generic\",\"example_qlt_${TAG}_site\",\"example_qlt\",\"callback.example.com\",18081,\"/upload\",\"PUT\",\"none\"]"
    expect "${N}/01: an Advanced Routing application and a subscription of the account to the folder" "$(payload $((off + 2)) | jq -c '[.type, .name]'):$(payload $((off + 3)) | jq -c '[.type, .account, .application, .folder]')" \
        "[\"AdvancedRouting\",\"example_qlt_${TAG}_app\"]:[\"AdvancedRouting\",\"example_qlt\",\"example_qlt_${TAG}_app\",\"/${FOLDER}\"]"
    expect "${N}/01: the template route" "$(payload $((off + 4)) | jq -c '[.type, .name, .conditionType]')" "[\"TEMPLATE\",\"example_qlt_${TAG}_template\",\"MATCH_ALL\"]"
    expect "${N}/01: the simple route has the steps of the scenario" "$(payload $((off + 5)) | jq -c '[.type, [.steps[] | .type]]')" "[\"SIMPLE\",${STEPS}]"
    expect "${N}/01: the Send To Partner step names the site, and takes the files of the step before only after Fusion" \
        "$(payload $((off + 5)) | jq -c '[.steps[] | select(.type == "SendToPartner") | [.transferSiteExpression, .usePrecedingStepFiles]]')" "[[\"example_qlt_${TAG}_site#!#CVD#!#\",$([ "${N}" = 2 ] && echo true || echo false)]]"
    expect "${N}/01: the composite route puts the simple one on the subscription of the template, by the ids of the Locations" \
        "$(payload $((off + 6)) | jq -c '[.type, .account, .routeTemplate, .subscriptions, [.steps[] | .executeRoute]]')" '["COMPOSITE","example_qlt","ID4",["ID3"],["ID5"]]'
    expect "${N}/01: the ids are written down, as they come" "$(tr '\n' ' ' < "${DIR}/state.local.objects")" "site=ID1 application=example_qlt_${TAG}_app subscription=ID3 template=ID4 simple=ID5 composite=ID6 "
    if [ "${N}" = 2 ]; then
        expect "${N}/01: the Fusion integration: the registry gets the name added to what was there" "$(payload 1 | jq -c .)" '[{"name":"Fusion.Integrations.Registry","values":["myFusion","example_qlt_fusion"]}]'
        expect "${N}/01: then its options: the endpoint of the fake server, Basic, the file and its metadata out, the file back, fake credentials" \
            "$(payload 2 | jq -c 'map([(.name | sub("Fusion.Integrations.Registry.example_qlt_fusion."; "")), .values[0]])')" \
            '[["fusionEndpoint","http://callback.example.com:18081/fusion"],["authType","BASIC"],["dataSent","ALL"],["dataExpected","PAYLOAD"],["username","fusion-fake-user"],["password","fusion-fake-secret"],["verifyCertificate","false"]]'
        expect "${N}/01: the simple route names the integration" "$(payload $((off + 5)) | jq -c '[.steps[0] | .type, .fusionIntegrationName]')" '["SendToFusion","example_qlt_fusion"]'
        expect "${N}/01: the Fusion options are kept first, the 3 of the server" "$(jq -c 'keys | length' "${UC}/state.local.fusion.json")" "3"
    else
        expect "${N}/01: no Fusion option is touched" "$(ucalls | grep -c 'configurations/options')" "0"
    fi
    run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: objects that are made already: exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    rm -f "${DIR}/state.local.objects" "${UC}/state.local.fusion.json"
    POST_SEQ="201 400" POST_BODY="$(body e${N}1 '{"validationErrors":["no such zone"]}')" RULES="$(RULES_COMMON)" run "${DIR}" 01.objects_POST.sh
    expect "${N}/01: a POST that is refused is exit 1 with the reason, and the next ones are not sent" "${RC}:$(ucalls | grep -c '^POST')" "1:2"
    has "${N}/01: the reason" "no such zone"
    rm -f "${DIR}/state.local.objects" "${UC}/state.local.fusion.json"
    RULES="$(RULES_COMMON)" run "${DIR}" 01.objects_POST.sh >/dev/null

    # -- 02 the flow
    start_decoy
    RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: exit 0" "${RC}" "0"
    expect "${N}/02: the case file is deleted, the overflow file is turned to it, the file is uploaded to the folder, the route is waited for, the overflow file is turned away" \
        "$(short | sed 's/events?accountName=example_qlt&limit=5/events/g')" "DELETE EU:files/${CASE} PATCH configurations/sentinel POST EU:files/${FOLDER} $(printf 'GET events %.0s' $(seq 1 "${REQS}"))PATCH configurations/sentinel "
    expect "${N}/02: the first patch turns the overflow file to the case file in the home of the account" "$(payload 1 | jq -c .)" "[{\"op\":\"replace\",\"path\":\"/overflowFilePath\",\"value\":\"/home/example_qlt/${CASE}\"}]"
    expect "${N}/02: the second turns it to the reads file" "$(payload 2 | jq -c .)" '[{"op":"replace","path":"/overflowFilePath","value":"/home/example_qlt/qlt_reads.dat"}]'
    expect "${N}/02: the upload is as the account, with its password, a file named ${TAG}_ and the time" "$(printf '%s\n' "${OUT}" | grep -c "^BASIC_AUTH: example_qlt:${PW}"):$(printf '%s\n' "${OUT}" | grep -c "filename=${TAG}_[0-9]*\.txt")" "2:1"
    expect "${N}/02: the name of the uploaded file is kept, and the time window, in RFC 2822" "$(grep -c "^${TAG}_[0-9]*\.txt$" "${DIR}/state.local.upload"):$(grep -cE '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$' "${DIR}/state.local.window")" "1:1"
    expect "${N}/02: what the fake server was sent is kept: ${REQS} line(s) at least" "$([ "$(wc -l < "${DIR}/state.local.requests.txt" | tr -d ' ')" -ge "${REQS}" ] && echo ok || echo few)" "ok"
    has "${N}/02: it says the file is turned away" "The overflow file is qlt_reads.dat again"
    start_decoy
    DELETE_STATUS=204 RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    has "${N}/02: a case file of an earlier run is deleted, and it says so" "starts clean"
    start_decoy
    DELETE_STATUS=404 RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    hasnt "${N}/02: no earlier file (404) is not mentioned" "starts clean"
    start_decoy
    POST_STATUS=403 RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: an upload that is refused is exit 1, and the overflow file is turned away all the same" "${RC}:$(ucalls | grep -c '^PATCH')" "1:2"
    has "${N}/02: it says the status" "HTTP 403"
    start_decoy
    POST_STATUS=000 RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    has "${N}/02: no answer from the End User port names the setting" "set ST_ENDUSER_PORT in set_variables.local.sh"
    start_decoy
    SLEEP_ADDS=0 RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: a fake server that is sent nothing: 40 asks, exit 1, the overflow file turned away" "${RC}:$(ucalls | grep -c 'events?accountName'):$(ucalls | grep -c '^PATCH')" "1:40:2"
    has "${N}/02: it asks whether the server reaches the callback address" "Does the SecureTransport server reach callback.example.com:18081?"
    start_decoy
    RULES="$(rules 'configurations/sentinel' "${SENTINEL_CHANGED}" 'events' "${EVENTS_STUCK}")" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: events of the account that never finish: it waits the 40 asks, and the overflow file is turned away" "${RC}:$(ucalls | grep -c 'events?accountName'):$(ucalls | grep -c '^PATCH')" "0:40:2"
    start_decoy
    PATCH_SEQ="400" OTHER_BODY="$(body e${N}2 '{"validationErrors":["no such path"]}')" RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: a first patch that is refused is exit 1, with nothing uploaded" "${RC}:$(ucalls | grep -c '^POST')" "1:0"
    stop_decoy
    RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: no fake server is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    has "${N}/02: it says to start it" "04.fakeServer_start.sh"
    cp "${DIR}/state.local.objects" "${WORK}/objects_keep"; rm -f "${DIR}/state.local.objects"
    start_decoy
    RULES="$(RULES_COMMON)" run "${DIR}" 02.flow_POST.sh
    expect "${N}/02: no objects is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    cp "${WORK}/objects_keep" "${DIR}/state.local.objects"
    run "${DIR}" 02.flow_POST.sh now
    expect "${N}/02: a parameter is exit 2" "${RC}" "2"
    stop_decoy

    # -- 03 the events
    rm -f "${DIR}/state.local.upload" "${DIR}/state.local.window"
    run "${DIR}" 03.events_GET.sh
    expect "${N}/03: no flow is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    printf '%s\n' "${UPLOAD}" > "${DIR}/state.local.upload"; printf '%s\n' "${WINDOW}" > "${DIR}/state.local.window"; printf '%s\n' "${REQLINES}" > "${DIR}/state.local.requests.txt"
    RULES="$(rules "files/${CASE}" "${EVTFILE}")" run "${DIR}" 03.events_GET.sh
    expect "${N}/03: exit 0, one GET of the case file as the account, with its password" "${RC}:$(short_all):$(printf '%s\n' "${OUT}" | grep '^BASIC_AUTH:' | sort -u)" "0:GET EU:files/${CASE} :BASIC_AUTH: example_qlt:${PW}"
    local count; count="$(grep -c '' "${DIR}/state.local.events.txt")"
    has "${N}/03: the count of events" "holds ${count} events"
    expect "${N}/03: each kept line is one whole document, though a record has nothing before it" "$(grep -c '^<?xml.*</TrkDescriptor>$' "${DIR}/state.local.events.txt")" "${count}"
    has "${N}/03: a login, with its action" "AUDIT         LOGIN_START"
    has "${N}/03: the first event of the transfer" "XFBTransfer   RECEIVING                R   ${UPLOAD}"
    expect "${N}/03: the event that follows a record with nothing between them is not lost: the SENT of the flow is in the kept events" "$(grep -c 'val="SENT"' "${DIR}/state.local.events.txt")" "$([ "${N}" = 1 ] && echo 1 || echo 2)"
    has "${N}/03: a CycleLink is named, with what it links" "CycleLink     XFBTransfer -> XFBTransfer"
    has "${N}/03: the route's event" "XFBRouting    POST_PROC"
    has "${N}/03: the kinds are counted" "Kinds: "
    has "${N}/03: the requests of the fake server are shown" "$(printf '%s\n' "${REQLINES}" | head -1 | jq -r '"\(.method) \(.path)  \(.bytes) bytes  the file \(.file)  answered \(.answer)"')"
    RULES="$(rules "files/${CASE}" "${EVTFILE}")" run "${DIR}" 03.events_GET.sh raw
    has "${N}/03: raw prints the attributes that have a value, sorted" "$(printf '  %-22s %s' COREID "core-${N}")"
    hasnt "${N}/03: and not the attribute that has none" "TLSVERSION"
    RULES="$(rules "files/${CASE}" "${EVTBAD}")" run "${DIR}" 03.events_GET.sh
    expect "${N}/03: a file without the end of the flow is asked 12 times, then exit 1" "${RC}:$(calls | grep -c "files/${CASE}")" "1:12"
    RULES="$(rules "files/${CASE}" "${CASE_EMPTY}")" GET_STATUS=404 run "${DIR}" 03.events_GET.sh
    expect "${N}/03: a case file that is not there is exit 1, asked once" "${RC}:$(calls | grep -c "files/${CASE}")" "1:1"
    has "${N}/03: it asks whether the flow ran" "Did 02.flow_POST.sh run"
    RULES="$(rules "files/${CASE}" "${EVTFILE}")" GET_STATUS=000 run "${DIR}" 03.events_GET.sh
    has "${N}/03: no answer from the End User port names the setting" "set ST_ENDUSER_PORT in set_variables.local.sh"
    RULES="$(rules "files/${CASE}" "${EVTFILE}")" GET_STATUS=403 run "${DIR}" 03.events_GET.sh
    has "${N}/03: any other refusal says the status" "Downloading ${CASE}: HTTP 403"
    run "${DIR}" 03.events_GET.sh nope
    expect "${N}/03: a parameter that is not raw is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
    run "${DIR}" 03.events_GET.sh raw more
    expect "${N}/03: two parameters are exit 2" "${RC}:$(ncalls)" "2:0"
    RULES="$(rules "files/${CASE}" "${EVTFILE}")" run "${DIR}" 03.events_GET.sh >/dev/null

    # -- 04 the ties to the log
    RULES="$(rules 'logs/transfers' "${LOGFILE}")" run "${DIR}" 04.logsTransfers_GET.sh
    expect "${N}/04: exit 0, one read of the transfer log, after the window" "${RC}:$(short)" "0:GET logs/transfers?account=example_qlt&startTimeAfter=${WINDOW}&limit=100 "
    has "${N}/04: the coreId" "    coreId  core-${N}"
    has "${N}/04: the events that carry it" "    events with this coreId:  "
    hasnt "${N}/04: the case file is not listed as a transfer" "qlt_1_upload_push.dat ("
    hasnt "${N}/04: the reads file is not listed" "qlt_reads.dat ("
    has "${N}/04: the verdict" "Every transfer of the flow in the log has events that carry its coreId."
    RULES="$(rules 'logs/transfers' "${LOG1_LOST}")" run "${DIR}" 04.logsTransfers_GET.sh
    expect "${N}/04: a transfer whose coreId is on no event is exit 1" "${RC}" "1"
    has "${N}/04: it says so" "no event carries this coreId"
    RULES="$(rules 'logs/transfers' "${LOG_NONE}")" run "${DIR}" 04.logsTransfers_GET.sh
    expect "${N}/04: a log with no transfer of the flow is exit 1" "${RC}" "1"
    GET_STATUS=500 RULES="$(rules 'logs/transfers' "${WORK}/e1.json")" run "${DIR}" 04.logsTransfers_GET.sh
    expect "${N}/04: a refused read is exit 1" "${RC}" "1"
    cp "${DIR}/state.local.events.txt" "${WORK}/events_keep"; rm -f "${DIR}/state.local.events.txt"
    run "${DIR}" 04.logsTransfers_GET.sh
    expect "${N}/04: no events is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
    run "${DIR}" 04.logsTransfers_GET.sh now
    expect "${N}/04: a parameter is exit 2" "${RC}" "2"

    # -- 99 the objects
    rm -f "${UC}/state.local.fusion.json"
    jq -S '[.result[] | {key: .name, value: .values}] | from_entries' "${FUSION_OPTS}" > "${WORK}/fusion_copy.json"
    [ "${N}" = 2 ] && cp "${WORK}/fusion_copy.json" "${UC}/state.local.fusion.json"
    cat > "${DIR}/state.local.objects" <<OBJ
site=ID1
application=example_qlt_${TAG}_app
subscription=ID3
template=ID4
simple=ID5
composite=ID6
OBJ
    RULES="$(rules 'configurations/options' "${FUSION_OPTS}" 'events' "${EVENTS_NONE}")" run "${DIR}" 99.objects_DELETE.sh
    expect "${N}/99: exit 0: the three routes, the subscription, the application, the site, the events read$([ "${N}" = 2 ] && echo ', the Fusion registry put back and read')" "${RC}:$(short | sed 's/events?accountName=example_qlt&limit=100/events/')" \
        "0:DELETE routes/ID6 DELETE routes/ID5 DELETE routes/ID4 DELETE subscriptions/ID3 DELETE applications/example_qlt_${TAG}_app DELETE sites/ID1 GET events$([ "${N}" = 2 ] && echo ' PUT configurations/options GET configurations/options?name=Fusion.Integrations*&limit=200') "
    expect "${N}/99: the state files of the scenario are gone" "$(ls "${DIR}"/state.local.* 2>/dev/null | wc -l | tr -d ' ')" "0"
    if [ "${N}" = 2 ]; then
        has "${N}/99: the Fusion options read back are the same" "The Fusion options read back are the same as before, key by key."
        expect "${N}/99: the registry is put back to what it was" "$(payload 1 | jq -c .)" '[{"name":"Fusion.Integrations.Registry","values":["myFusion"]}]'
        expect "${N}/99: and the copy of the Fusion options is removed" "$(test -e "${UC}/state.local.fusion.json" && echo kept || echo gone)" "gone"
    fi
    run "${DIR}" 99.objects_DELETE.sh
    expect "${N}/99: a second time, with nothing written down: nothing is deleted, exit 0" "${RC}:$(ucalls | grep -c '^DELETE')" "0:0"
    printf 'site=ID1\ncomposite=ID6\n' > "${DIR}/state.local.objects"
    DELETE_STATUS=404 RULES="$(rules 'events' "${EVENTS_NONE}")" run "${DIR}" 99.objects_DELETE.sh
    expect "${N}/99: objects that are not there (404) are fine: exit 0" "${RC}" "0"
    printf 'composite=ID6\n' > "${DIR}/state.local.objects"
    DELETE_STATUS=500 RULES="$(rules 'events' "${EVENTS_NONE}")" run "${DIR}" 99.objects_DELETE.sh
    expect "${N}/99: a delete that is refused is exit 1" "${RC}" "1"
    has "${N}/99: it says which" "could not be deleted (HTTP 500)"
    printf 'composite=ID6\n' > "${DIR}/state.local.objects"
    RULES="$(rules 'events' "${EVENTS_STUCK}")" run "${DIR}" 99.objects_DELETE.sh
    expect "${N}/99: events of the account that are left are deleted, by their ids" "$(ucalls | grep -c 'events/operations?operation=delete'):$(payload 1 | jq -c .)" '1:{"ids":["0xSTUCK1"]}'
    if [ "${N}" = 2 ]; then
        cp "${WORK}/fusion_copy.json" "${UC}/state.local.fusion.json"
        printf 'composite=ID6\n' > "${DIR}/state.local.objects"
        RULES="$(rules 'configurations/options' "${FUSION_OPTS_MOVED}" 'events' "${EVENTS_NONE}")" run "${DIR}" 99.objects_DELETE.sh
        expect "${N}/99: Fusion options that are not the copy afterwards are exit 1, and the copy is kept" "${RC}:$(test -e "${UC}/state.local.fusion.json" && echo kept || echo gone)" "1:kept"
        has "${N}/99: it lists the option that differs" "Fusion.Integrations.Registry"
        rm -f "${UC}/state.local.fusion.json"
    fi
    rm -f "${DIR}"/state.local.*
}
scenario_tests 1 "${S1}" push qlt_push_in qlt_1_upload_push.dat '["SendToPartner"]' 1 "${UPLOAD1}" "${CASE1}" "${CASE1_NOSENT}" "${LOG1}" "${REQUESTS_1}"
scenario_tests 2 "${S2}" fusion qlt_fusion_in qlt_2_upload_fusion_partner.dat '["SendToFusion","SendToPartner"]' 2 "${UPLOAD2}" "${CASE2}" "${CASE2_NOFINAL}" "${LOG2}" "${REQUESTS_2}"
clean_all

echo "=== 99 the cleanup ==="
set_password; set_copy "${SENTINEL}"; start_decoy; DECOY_ALIVE_BEFORE="$(ps -o command= -p "${DECOY_PID}" | grep -c fake_http_server)"
printf 'composite=ID6\n' > "${S1}/state.local.objects"
RULES="$(rules 'configurations/sentinel' "${SENTINEL}" 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: exit 0" "${RC}" "0"
expect "99: the scenarios first, then the copy sent back and read, then the files and the account, the session last" "$(short | sed 's/events?accountName=example_qlt&limit=100/events/g; s/GET myself //g')" \
    "DELETE routes/ID6 GET events GET events PUT configurations/sentinel GET configurations/sentinel GET EU:files DELETE EU:files/qlt_1_upload_push.dat DELETE EU:files/qlt_reads.dat DELETE accounts/example_qlt DELETE myself "
expect "99: the body of the PUT is the copy" "$(payload 1 | jq -S . | md5sum | cut -c1-32 2>/dev/null || payload 1 | jq -S . | md5)" "$(jq -S . "${SENTINEL}" | md5sum | cut -c1-32 2>/dev/null || jq -S . "${SENTINEL}" | md5)"
has "99: it says the settings are the same" "The settings read back are the same as the copy, key by key."
has "99: it deletes an overflow file" "The file qlt_1_upload_push.dat was deleted."
hasnt "99: a folder in the listing is not deleted" "qlt_push_in was deleted"
expect "99: the fake server is stopped (the process is gone), and says so" "${DECOY_ALIVE_BEFORE}:$(ps -o command= -p "${DECOY_PID}" 2>/dev/null | grep -c fake_http_server):$(printf '%s\n' "${OUT}" | grep -c 'was stopped')" "1:0:1"
DECOY_PID=""
expect "99: no file of the use case is left" "$(ls "${UC}"/state.local.* "${UC}/session.cookie.jar" 2>/dev/null | wc -l | tr -d ' ')" "0"
clean_all; set_password; set_copy "${SENTINEL}"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_CHANGED}" 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: settings that are not the copy afterwards are exit 1, and the copy is kept" "${RC}:$(test -e "${UC}/state.local.sentinel.json" && echo kept || echo gone)" "1:kept"
has "99: it lists the keys that differ" '  "host"'
has "99: the files and the account are cleaned up all the same" "The account example_qlt was deleted."
clean_all; set_password; set_copy "${SENTINEL}"
PUT_STATUS=400 OTHER_BODY="$(body e99 '{"validationErrors":["nope"]}')" RULES="$(rules 'configurations/sentinel' "${SENTINEL}" 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: a PUT that is refused is exit 1, with the reason, and the rest is done" "${RC}:$(ucalls | grep -c '^DELETE')" "1:4"
has "99: the reason" "Sending the copy back: HTTP 400"
clean_all; set_password; set_copy "${SENTINEL_BARE}"
RULES="$(rules 'configurations/sentinel' "${SENTINEL_BARE_AFTER}" 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: a server that had no host: reporting off with the current settings, then the options, no PUT of the copy" "${RC}:$(short | sed 's/events?accountName=example_qlt&limit=100/events/g; s/GET myself //g' | sed 's/ DELETE.*//' | sed 's/^GET events GET events //')" "0:GET configurations/sentinel PUT configurations/sentinel PUT configurations/options GET configurations/sentinel GET EU:files"
expect "99: the options clear the host and the path, and set the port, the size and the threshold to what the copy had" "$(payload 2 | jq -c '[.[] | [.name, .values[0]]]')" \
    '[["AxwaySentinel.RemoteHost.host",""],["AxwaySentinel.OverflowFile.path",""],["AxwaySentinel.RemoteHost.port","1305"],["AxwaySentinel.OverflowFile.size",""],["AxwaySentinel.OverflowFile.threshold",""]]'
has "99: the size, the threshold and the states the server keeps do not count as a difference" "The settings read back are the same as the copy, key by key."
clean_all; set_password
RULES="$(rules 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: with no copy the settings are not touched: no PUT, no read of them" "${RC}:$(ucalls | grep -c 'configurations')" "0:0"
has "99: it says so" "There is no copy of the settings (step 02 did not run)"
has "99: and that the fake server was not running" "The fake HTTP server was not running."
clean_all
DELETE_STATUS=404 RULES="$(rules 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: with no password the files are left, and an account that is not there (404) is fine: exit 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'There is no password')" "0:1"
has "99: and that the account was not there" "The account example_qlt was not there."
set_password
DELETE_STATUS=500 RULES="$(rules 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" run "${UC}" 99.cleanup_DELETE.sh
expect "99: a delete that is refused is exit 1, for each file and the account" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'could not be deleted')" "1:3"
clean_all; set_password
RULES="$(rules 'events' "${EVENTS_NONE}" '/files' "${LISTING}")" GET_SEQ="200 200 200 403" run "${UC}" 99.cleanup_DELETE.sh
has "99: a listing that is refused leaves the files and goes on to the account" "could not be listed: they are left."
run "${UC}" 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
clean_all

echo "=== 00 all the steps ==="
start_decoy
RULES="$(rules 'configurations/sentinel' "${SENTINEL_ALL_ON}" 'configurations/options' "${FUSION_OPTS}" 'events' "${EVENTS_NONE}" 'logs/transfers' "${LOG_ALL}" "files/qlt_1_upload_push.dat" "${CASE1}" "files/qlt_2_upload_fusion_partner.dat" "${CASE2}" '/files' "${LISTING}")" run "${UC}" 00.run_all.sh
expect "00: the steps run in order, the cleanup last" "$(printf '%s\n' "${OUT}" | sed -n 's/^=== \(.*\) ===$/\1/p' | tr '\n' ' ')" \
    "01.accounts_POST 02.sentinel_GET 03.sentinel_PATCH 04.fakeServer_start 1-upload-push/01.objects_POST 1-upload-push/02.flow_POST 1-upload-push/03.events_GET 1-upload-push/04.logsTransfers_GET 1-upload-push/99.objects_DELETE 2-upload-fusion-partner/01.objects_POST 2-upload-fusion-partner/02.flow_POST 2-upload-fusion-partner/03.events_GET 2-upload-fusion-partner/04.logsTransfers_GET 2-upload-fusion-partner/99.objects_DELETE 99.cleanup_DELETE "
stop_decoy; clean_all
PATCH_STATUS=400 RULES="$(rules 'configurations/sentinel' "${SENTINEL_ALL_ON}")" run "${UC}" 00.run_all.sh
expect "00: a step that fails stops the run, is named, and the cleanup still runs: exit 1" "${RC}" "1"
has "00: it names the step" "03.sentinel_PATCH failed."
hasnt "00: the steps after it do not run" "=== 04.fakeServer_start ==="
has "00: the cleanup runs" "=== 99.cleanup_DELETE ==="
clean_all
run "${UC}" 00.run_all.sh now
expect "00: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
clean_all

echo "=== the folder and the README ==="
for f in 00.run_all 01.accounts_POST 02.sentinel_GET 03.sentinel_PATCH 04.fakeServer_start 99.cleanup_DELETE 1-upload-push/01.objects_POST 1-upload-push/02.flow_POST 1-upload-push/03.events_GET \
         1-upload-push/04.logsTransfers_GET 1-upload-push/99.objects_DELETE 2-upload-fusion-partner/01.objects_POST 2-upload-fusion-partner/02.flow_POST 2-upload-fusion-partner/03.events_GET \
         2-upload-fusion-partner/04.logsTransfers_GET 2-upload-fusion-partner/99.objects_DELETE; do
    [ -x "${UC_ROOT}/10-qlt-events-generation/${f}.sh" ] && pass "${f}.sh is there and executable" || fail "${f}.sh is missing or not executable"
done
for s in "${UC_ROOT}"/10-qlt-events-generation/*.sh "${UC_ROOT}"/10-qlt-events-generation/*/*.sh; do
    case "$(basename "${s}")" in lib.sh|scenario.sh|00.*|99.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/[^ ,]*\.sh).*/\1/p' "${s}" | head -1)
    n="${s#"${UC_ROOT}/10-qlt-events-generation/"}"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done
python3 - "${README_FILE}" "${UC_ROOT}/10-qlt-events-generation" "${UC_ROOT}/README.md" <<'PY' && pass "README: the sections, the warnings, the scenarios, the steps are the files, the claims, the index" || fail "README: see above"
import os, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
folder = sys.argv[2]
index = open(sys.argv[3], encoding="utf-8").read()
for heading in ("## What it changes, and for how long", "## The idea", "## The two scenarios", "## The steps", "## What you see", "## What the events are", "## What was tried", "## Things to know", "## Not covered", "## The files"):
    assert heading in text, heading
for needle in ("192.0.2.1", "RFC 5737", "Circular buffer file version", "coreId", "localId", "XFBTransfer", "XFBRouting", "CycleLink", "AUDIT", "overflow file", "99.cleanup_DELETE.sh", "ST_CALLBACK_HOST",
               "fake HTTP server", "Send To Fusion", "Send To Partner", "Generic HTTP", "http-generic", "Fusion.Integrations.Registry", "qlt_reads.dat", "`stop` would pause **every transfer of the server**",
               "none reaches a real Sentinel", "5.5-20261029", "host must not be null or empty", "not tried", "every state"):
    assert needle in text, needle
scripts = sorted(f[:-3] for f in os.listdir(folder) if f.endswith(".sh") and f not in ("lib.sh", "scenario.sh"))
named = re.findall(r"`(\d\d\.[A-Za-z]+_[A-Za-z_]+)\.sh", text)
for s in scripts:
    assert s in named, "the README does not name " + s
for scenario in sorted(d for d in os.listdir(folder) if re.match(r"\d-", d)):
    assert scenario in text, scenario
    for f in sorted(x[:-3] for x in os.listdir(os.path.join(folder, scenario)) if x.endswith(".sh") and x != "lib.sh"):
        assert f in text, scenario + "/" + f
for n in named:
    assert os.path.exists(os.path.join(folder, n + ".sh")) or any(os.path.exists(os.path.join(folder, d, n + ".sh")) for d in os.listdir(folder) if re.match(r"\d-", d)), n
assert os.path.isfile(os.path.join(folder, "fake_http_server.py")) and "fake_http_server.py" in text
assert "10-qlt-events-generation/README.md" in index and "QLT events generation (10)" in index
PY

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_10: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_10: PASS"
