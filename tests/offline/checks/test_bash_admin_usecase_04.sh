#!/bin/bash
# ==============================================================================
# Run the Admin use case 04-stopping-and-starting-servers against a stub curl, and check the calls each
# script makes (method, URL and query, headers) and what it does with the answers: its exit code and the
# message for each way it can fail.
#
# 01: the daemons and the servers read, and the copy saved. 02: the stop (the confirmation word, a graceful
# that is not true or false refused before any call, a stop that is accepted, one that answers 200 with
# isSuccessful false, one refused, a daemon already stopped). 03: the wait loop against a sequence of
# statuses (how long it counted, the timeout). 04: the start. 05: the wait for the servers, the start of a
# server that stays down. 06: the comparison with the copy, each kind of difference. 99: what it puts back
# (the daemon, a server), what it never touches (as2), twice. 00: the whole run, and a failing step that stops
# it and still cleans up.
#
# Runs offline, with the Referer and Content-Type rules of the stub on. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_04"
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
# a clock that does not move, so that the seconds a wait reports are the ones it counted (POLL for each poll)
printf '#!/bin/bash\necho 1000\n' > "${WORK}/bin/date" && chmod +x "${WORK}/bin/date"

cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/04-stopping-and-starting-servers" "${WORK}/tree/UseCases/"
UC="${WORK}/tree/UseCases/04-stopping-and-starting-servers"
rm -f "${UC}"/state.local.* "${UC}/session.cookie.jar"
BASE="https://st.example.com:8444/api/v2.0"
NL=$'\n'

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
rules() {
    local out   # made in a subshell, so a counter would not count: a file of its own for each call
    out="$(mktemp "${WORK}/rules_XXXXXX")"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# mkseq NAME FILE...: a folder in which the Nth GET of a run is answered with the Nth file, the last one repeating
mkseq() {
    local dir="${WORK}/seq_$1" n=0 f
    shift
    rm -rf "${dir}"; mkdir -p "${dir}"
    for f in "$@"; do n=$((n + 1)); cp "${f}" "${dir}/${n}.json"; done
    echo "${dir}"
}
# the same file, N times
rep() { local n="$1" f="$2" out=(); while [ "${n}" -gt 0 ]; do out+=("${f}"); n=$((n - 1)); done; echo "${out[@]}"; }

echo '{"loginName":"admin"}' > "${WORK}/me.json"
D_RUN="$(body d_run '{"ftpStatus":"Running","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Running","as2Status":"Not running"}')"
D_DOWN="$(body d_down '{"ftpStatus":"Not running","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Running","as2Status":"Not running"}')"
D_GRACE="$(body d_grace '{"ftpStatus":"Graceful shutdown in progress.","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Running","as2Status":"Not running"}')"
D_SSHDOWN="$(body d_sshdown '{"ftpStatus":"Running","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Not running","as2Status":"Not running"}')"
S_ACT="$(body s_act '{"resultSet":{"returnCount":3,"totalCount":3},"result":[{"protocol":"http","serverName":"Http Default","isActive":true},{"protocol":"ftp","serverName":"Ftp Default","isActive":true},{"protocol":"as2","serverName":"As2 Default","isActive":false}]}')"
S_OFF="$(body s_off '{"resultSet":{"returnCount":3,"totalCount":3},"result":[{"protocol":"http","serverName":"Http Default","isActive":true},{"protocol":"ftp","serverName":"Ftp Default","isActive":false},{"protocol":"as2","serverName":"As2 Default","isActive":false}]}')"
S_NEW="$(body s_new '{"resultSet":{"returnCount":4,"totalCount":4},"result":[{"protocol":"http","serverName":"Http Default","isActive":true},{"protocol":"ftp","serverName":"Ftp Default","isActive":true},{"protocol":"ftp","serverName":"Ftp Extra","isActive":true},{"protocol":"as2","serverName":"As2 Default","isActive":false}]}')"
S_GONE="$(body s_gone '{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"protocol":"http","serverName":"Http Default","isActive":true},{"protocol":"as2","serverName":"As2 Default","isActive":false}]}')"
OK_STOP="$(body ok_stop '[{"daemon":"FTP","message":"Daemon FTP is stopped.","isSuccessful":true}]')"
OK_START="$(body ok_start '[{"daemon":"FTP","message":"Daemon FTP is started.","isSuccessful":true}]')"
NO_STOP="$(body no_stop '[{"daemon":"FTP","message":"Daemon FTP is already stopped.","isSuccessful":false}]')"
NO_START="$(body no_start '[{"daemon":"FTP","message":"Daemon FTP is already started.","isSuccessful":false}]')"
OBJ_STOP="$(body obj_stop '{"daemonOperationResults":[{"daemon":"FTP","message":"Daemon FTP is stopped.","isSuccessful":true}]}')"
SRV_OK="$(body srv_ok '{"serverStatuses":[{"serverName":"Ftp Default","message":"Server Ftp Default is started.","isSuccessful":true}]}')"
SRV_NO="$(body srv_no '{"serverStatuses":[{"serverName":"Ftp Default","message":"Server Ftp Default can not be started.","isSuccessful":false}]}')"
REFUSED="$(body refused '{"message":"Error validating request","validationErrors":["Not correct daemon type: nope."]}')"
RUNNING_RULES="$(rules "/daemons" "${D_RUN}" "/servers" "${S_ACT}")"

# run SCRIPT [PARAMETER...]: in the use case folder, with the answers the variables name; urun puts a session jar in place first
run() {
    local rel="$1"; shift
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/me.json}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_CSRF="${CSRF:-}" \
          STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
urun() { touch "${UC}/session.cookie.jar"; echo "tok123" > "${UC}/state.local.csrf"; run "$@"; }
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | wc -l | tr -d ' '; }
npost() { calls | grep -c '^POST '; }
# hdrs_of METHOD: the headers of the call with that method (they are printed before its METHOD line)
hdrs_of() { printf '%s\n' "${OUT}" | awk -v M="$1" '/^HEADER:/ {b = b $0 "\n"} /^METHOD:/ {if ($2 == M) r = b; b = ""} END {printf "%s", r}' | sed 's/^HEADER: //'; }
clear_state() { rm -f "${UC}"/state.local.* "${UC}/session.cookie.jar"; }
# the copy of the start, as 01 makes it (what is running, which servers are active)
save_start() { RULES="${RUNNING_RULES}" urun 01.daemons_GET.sh; }
RULES=""

echo "=== 01 look, and keep a copy ==="
clear_state
RULES="${RUNNING_RULES}" urun 01.daemons_GET.sh
expect "01: reads the daemons and the servers, after the session check" "$(calls)" \
    "GET ${BASE}/myself${NL}GET ${BASE}/daemons${NL}GET ${BASE}/servers?fields=serverName,isActive&limit=1000"
has "01: the session is the cookie jar" "COOKIE: ${UC}/session.cookie.jar"
has "01: names each daemon and its status" "ftp	Running"
has "01: and a daemon that is not running" "as2	Not running"
has "01: names each server with its protocol" "ftp	Ftp Default	active"
has "01: and a server that is not active" "as2	As2 Default	not active"
expect "01: saves the daemons" "$(jq -r .ftpStatus "${UC}/state.local.daemons.json")" "Running"
expect "01: saves the servers, sorted by name, with their protocol and isActive" "$(jq -c '[.[] | [.serverName, .protocol, .isActive]]' "${UC}/state.local.servers.json")" \
    '[["As2 Default","as2",false],["Ftp Default","ftp",true],["Http Default","http",true]]'
expect "01: exit 0" "${RC}" "0"
RULES="${RUNNING_RULES}" urun 01.daemons_GET.sh extra
expect "01: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: with the usage" "Usage: ./01.daemons_GET.sh"
clear_state
STATUS_GET=500 urun 01.daemons_GET.sh
expect "01: a daemons answer that is not 200 is exit 1" "${RC}" "1"
has "01: and says which call" "GET /daemons: HTTP 500"
expect "01: and saved nothing" "$(ls "${UC}"/state.local.daemons.json 2>/dev/null | wc -l | tr -d ' ')" "0"
RULES="${RUNNING_RULES}" STUB_STATUS_GET_SEQ="200 200 500" STUB_COUNTER="${WORK}/ctr01" urun 01.daemons_GET.sh
expect "01: a servers answer that is not 200 is exit 1" "${RC}" "1"
has "01: and says so" "Could not read the servers: HTTP 500"
expect "01: and saved no servers" "$(ls "${UC}"/state.local.servers.json 2>/dev/null | wc -l | tr -d ' ')" "0"

echo "=== 02 stop ==="
clear_state
urun 02.daemon_stop.sh
expect "02: no parameter: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: with the usage" "Usage: ./02.daemon_stop.sh DAEMON stop-the-DAEMON-daemon [GRACEFUL] [TIMEOUT]"
urun 02.daemon_stop.sh ftp
expect "02: no confirmation word: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: says which word to give" "give the word stop-the-ftp-daemon"
urun 02.daemon_stop.sh ftp stop-the-ssh-daemon
expect "02: the word of another daemon is not the word: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and says the daemon of the whole server stops" "This stops the ftp daemon of the whole server"
urun 02.daemon_stop.sh nope stop-the-nope-daemon
expect "02: a daemon that does not exist: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and names the daemons" "must be ftp, http, ssh, as2 or pesit"
urun 02.daemon_stop.sh nope
expect "02: a daemon that does not exist, with no word: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 02.daemon_stop.sh ftp stop-the-ftp-daemon yes
expect "02: GRACEFUL yes is refused before any call: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and says the server takes any text" "it must be true or false. The server does not check it"
urun 02.daemon_stop.sh ftp stop-the-ftp-daemon TRUE
expect "02: GRACEFUL TRUE (upper case) is refused too" "${RC}:$(ncalls)" "2:0"
urun 02.daemon_stop.sh ftp stop-the-ftp-daemon true abc
expect "02: a TIMEOUT that is not a number: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and says whole number" "it must be a whole number of seconds"
urun 02.daemon_stop.sh ftp stop-the-ftp-daemon false 30
expect "02: a TIMEOUT with GRACEFUL false: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and says why" "TIMEOUT only goes with GRACEFUL true"
urun 02.daemon_stop.sh ftp stop-the-ftp-daemon true 30 extra
expect "02: five parameters: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

RULES="${RUNNING_RULES}" POST_BODY="${OK_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon
expect "02: reads the status, then one POST that stops the daemon, graceful true written out" "$(calls)" \
    "GET ${BASE}/myself${NL}GET ${BASE}/daemons${NL}POST ${BASE}/daemons/operations?operation=stop&daemon=ftp&graceful=true"
has "02: the POST carries the Referer" "Referer: THIS_IS_A_RANDOM_TEXT"
expect "02: and the csrfToken of the session" "$(hdrs_of POST | grep -c '^csrfToken: tok123$')" "1"
has "02: shows the status before" "The ftp daemon is now: Running"
has "02: prints the result of the server" "FTP: Daemon FTP is stopped. (isSuccessful: true)"
has "02: says accepted is not stopped" "Accepted. That is not the same as stopped"
expect "02: exit 0" "${RC}" "0"
RULES="${RUNNING_RULES}" POST_BODY="${OK_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon false
expect "02: graceful false is sent as false" "$(calls | grep -c 'graceful=false$')" "1"
RULES="${RUNNING_RULES}" POST_BODY="${OK_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon true 45
expect "02: a timeout is sent after graceful" "$(calls | grep -c 'operation=stop&daemon=ftp&graceful=true&timeout=45$')" "1"
has "02: and said" "graceful=true, timeout=45"
RULES="${RUNNING_RULES}" POST_BODY="${OBJ_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon
expect "02: an answer that is an object with daemonOperationResults is read too: exit 0" "${RC}" "0"
has "02: and printed" "FTP: Daemon FTP is stopped."
RULES="${RUNNING_RULES}" POST_BODY="${NO_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon
expect "02: 200 with isSuccessful false is exit 1" "${RC}" "1"
has "02: shows the message of the server" "Daemon FTP is already stopped. (isSuccessful: false)"
has "02: and says the daemon was NOT stopped" "the daemon was NOT stopped"
hasnt "02: and does not say accepted" "Accepted."
RULES="${RUNNING_RULES}" POST_BODY="${REFUSED}" STUB_STATUS_POST=400 urun 02.daemon_stop.sh ftp stop-the-ftp-daemon
expect "02: a 400 is exit 1" "${RC}" "1"
has "02: shows the server's own message" "Not correct daemon type: nope."
has "02: and says nothing was stopped" "The server refused the call. Nothing was stopped."
RULES="$(rules "/daemons" "${D_DOWN}")" POST_BODY="${OK_STOP}" urun 02.daemon_stop.sh ftp stop-the-ftp-daemon
expect "02: a daemon that is not running is not asked to stop: no POST, exit 0" "${RC}:$(npost)" "0:0"
has "02: and says so" "It is already stopped: nothing was sent."

echo "=== 03 wait ==="
clear_state
urun 03.daemon_wait.sh
expect "03: no parameter: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "03: with the usage" "Usage: ./03.daemon_wait.sh DAEMON STATE [SECONDS]"
urun 03.daemon_wait.sh ftp
expect "03: no state: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 03.daemon_wait.sh ftp Stopped
expect "03: a state GET /daemons never says: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "03: and names the two" "must be Running or \"Not running\""
urun 03.daemon_wait.sh ftp running
expect "03: the state is case sensitive: exit 2" "${RC}:$(ncalls)" "2:0"
urun 03.daemon_wait.sh nope Running
expect "03: a daemon that does not exist: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 03.daemon_wait.sh ftp Running ten
expect "03: SECONDS that is not a number: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 03.daemon_wait.sh ftp Running 10 extra
expect "03: four parameters: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
RULES="${RUNNING_RULES}" urun 03.daemon_wait.sh ftp Running
expect "03: a daemon that is there already: one read after the session check, exit 0" "${RC}:$(calls | grep -c '/daemons$')" "0:1"
has "03: counted 0 seconds" "The ftp daemon says Running, after about 0 seconds."
STUB_CURL_GET_SEQUENCE="$(mkseq w1 "${WORK}/me.json" "${D_RUN}" "${D_RUN}" "${D_DOWN}")" urun 03.daemon_wait.sh ftp "Not running"
expect "03: waits through two answers that are not yet it: exit 0" "${RC}:$(calls | grep -c '/daemons$')" "0:3"
has "03: counted 6 seconds (2 polls of 3)" "The ftp daemon says Not running, after about 6 seconds."
has "03: said what it waits for" "Waiting for the ftp daemon to be 'Not running' (at most 60 seconds)"
STUB_CURL_GET_SEQUENCE="$(mkseq w2 "${WORK}/me.json" "${D_RUN}")" urun 03.daemon_wait.sh ftp "Not running" 6
expect "03: a daemon that stays as it is: exit 1 after 3 polls (at 0, 3 and 6 seconds)" "${RC}:$(calls | grep -c '/daemons$')" "1:3"
has "03: says how long it waited and what the last status was" "is not 'Not running' after 6 seconds (last status: Running)."
STUB_CURL_GET_SEQUENCE="$(mkseq w3 "${WORK}/me.json" "${D_RUN}")" urun 03.daemon_wait.sh ftp "Not running" 0
expect "03: SECONDS 0 asks once: exit 1 after one poll" "${RC}:$(calls | grep -c '/daemons$')" "1:1"
STATUS_GET=500 urun 03.daemon_wait.sh ftp Running 3
expect "03: a daemons answer that is not 200 counts as 'unknown' and times out: exit 1" "${RC}" "1"
has "03: and says the last status was unknown" "(last status: unknown)"
STUB_CURL_GET_SEQUENCE="$(mkseq g1 "${WORK}/me.json" "${D_RUN}" "${D_GRACE}" "${D_GRACE}" "${D_DOWN}")" urun 03.daemon_wait.sh ftp "Not running"
expect "03: the status the server gives while a graceful stop goes on is not Not running: it waits through it, then exit 0" "${RC}:$(calls | grep -c '/daemons$')" "0:4"
STUB_CURL_GET_SEQUENCE="$(mkseq g2 "${WORK}/me.json" "${D_GRACE}")" urun 03.daemon_wait.sh ftp "Not running" 3
expect "03: and a stop that does not finish in time is exit 1" "${RC}" "1"
has "03: that names the status it was still in" "(last status: Graceful shutdown in progress.)"
# a clock that moves 10 seconds each time it is read (the real case: a poll is a call as well as a sleep): the report is the clock's, not 3 for each poll
cp "${WORK}/bin/date" "${WORK}/bin/date_fixed"
printf '#!/bin/bash\nf="%s/clock"; n=$(( $(cat "$f" 2>/dev/null || echo 0) + 10 )); echo "$n" > "$f"; echo "$n"\n' "${WORK}" > "${WORK}/bin/date"
rm -f "${WORK}/clock"
STUB_CURL_GET_SEQUENCE="$(mkseq w5 "${WORK}/me.json" "${D_RUN}" "${D_RUN}" "${D_DOWN}")" urun 03.daemon_wait.sh ftp "Not running" 60
expect "03: when the clock is ahead of the count, the clock is what it reports" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'says Not running, after about 30 seconds.')" "0:1"
rm -f "${WORK}/clock"
STUB_CURL_GET_SEQUENCE="$(mkseq w6 "${WORK}/me.json" "${D_RUN}")" urun 03.daemon_wait.sh ftp "Not running" 20
expect "03: and the limit is the clock's too: 2 polls, not the 8 a count of 3 seconds each would make" "${RC}:$(calls | grep -c '/daemons$')" "1:2"
cp "${WORK}/bin/date_fixed" "${WORK}/bin/date"
STUB_CURL_GET_SEQUENCE="$(mkseq w4 "${WORK}/me.json" "${D_DOWN}" "${D_RUN}")" urun 03.daemon_wait.sh ssh Running
expect "03: another daemon is read by its own key: ssh is Running at once, exit 0" "${RC}" "0"

echo "=== 04 start ==="
clear_state
urun 04.daemon_start.sh
expect "04: no parameter: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "04: with the usage" "Usage: ./04.daemon_start.sh DAEMON"
urun 04.daemon_start.sh ftp extra
expect "04: two parameters: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 04.daemon_start.sh nope
expect "04: a daemon that does not exist: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
RULES="$(rules "/daemons" "${D_DOWN}")" POST_BODY="${OK_START}" urun 04.daemon_start.sh ftp
expect "04: reads the status, then one POST that starts the daemon" "$(calls)" \
    "GET ${BASE}/myself${NL}GET ${BASE}/daemons${NL}POST ${BASE}/daemons/operations?operation=start&daemon=ftp"
expect "04: the POST carries the csrfToken" "$(hdrs_of POST | grep -c '^csrfToken: tok123$')" "1"
has "04: shows the status before" "The ftp daemon is now: Not running"
has "04: prints the result of the server" "FTP: Daemon FTP is started. (isSuccessful: true)"
has "04: says the answer comes before the daemon is up" "Accepted. That is not the same as running"
expect "04: exit 0" "${RC}" "0"
RULES="$(rules "/daemons" "${D_DOWN}")" POST_BODY="${NO_START}" urun 04.daemon_start.sh ftp
expect "04: 200 with isSuccessful false is exit 1" "${RC}" "1"
has "04: and says the daemon was NOT started" "the daemon was NOT started"
RULES="$(rules "/daemons" "${D_DOWN}")" POST_BODY="${REFUSED}" STUB_STATUS_POST=403 urun 04.daemon_start.sh ftp
expect "04: a 403 is exit 1, with the server's message" "${RC}" "1"
has "04: and says nothing was started" "Nothing was started."
RULES="${RUNNING_RULES}" POST_BODY="${OK_START}" urun 04.daemon_start.sh ftp
expect "04: a daemon that is running is not asked to start: no POST, exit 0" "${RC}:$(npost)" "0:0"
has "04: and says so" "It is already running: nothing was sent."

echo "=== 05 wait for the servers ==="
clear_state
urun 05.servers_wait.sh
expect "05: no parameter: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "05: with the usage" "Usage: ./05.servers_wait.sh DAEMON [SECONDS]"
urun 05.servers_wait.sh nope
expect "05: a daemon that does not exist: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 05.servers_wait.sh ftp ten
expect "05: SECONDS that is not a number: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 05.servers_wait.sh ftp 5 extra
expect "05: three parameters: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
# no copy of the start: every server of the protocol is waited for
RULES="${RUNNING_RULES}" urun 05.servers_wait.sh ftp
expect "05: servers that are active: one read, no POST, exit 0" "${RC}:$(calls | grep -c '/servers?'):$(npost)" "0:1:0"
has "05: names them and counts 0 seconds" "The ftp servers (Ftp Default) are active, after about 0 seconds."
expect "05: asks for the name and isActive of up to 1000 servers" "$(calls | grep -c '/servers?fields=serverName,isActive&limit=1000$')" "1"
STUB_CURL_GET_SEQUENCE="$(mkseq s1 "${WORK}/me.json" "${S_OFF}" "${S_OFF}" "${S_ACT}")" urun 05.servers_wait.sh ftp
expect "05: waits until it is active: 3 reads, no POST, exit 0" "${RC}:$(calls | grep -c '/servers?'):$(npost)" "0:3:0"
has "05: counted 6 seconds" "after about 6 seconds."
# a server that stays down is started, and the wait runs again
STUB_CURL_GET_SEQUENCE="$(mkseq s2 "${WORK}/me.json" $(rep 3 "${S_OFF}") "${S_ACT}")" POST_BODY="${SRV_OK}" urun 05.servers_wait.sh ftp 3
expect "05: a server still down after the wait is started: one POST, exit 0" "${RC}:$(npost)" "0:1"
expect "05: the POST is to /servers/operations with the server's name and the operation start" "$(calls | grep -c '^POST .*/servers/operations?serverName=Ftp Default&operation=start$')" "1"
expect "05: and carries the csrfToken" "$(hdrs_of POST | grep -c '^csrfToken: tok123$')" "1"
has "05: says they did not come up by themselves" "They did not come up by themselves."
has "05: shows the result of the start" "Ftp Default: Server Ftp Default is started. (isSuccessful: true)"
has "05: and that the servers are active in the end" "The ftp servers (Ftp Default) are active"
STUB_CURL_GET_SEQUENCE="$(mkseq s3 "${WORK}/me.json" "${S_OFF}")" POST_BODY="${SRV_NO}" urun 05.servers_wait.sh ftp 3
expect "05: a start that answers 200 with isSuccessful false is exit 1" "${RC}" "1"
has "05: and says a server could not be started" "A server could not be started."
STUB_CURL_GET_SEQUENCE="$(mkseq s4 "${WORK}/me.json" "${S_OFF}")" POST_BODY="${SRV_OK}" urun 05.servers_wait.sh ftp 3
expect "05: a start that is accepted but the server stays down is exit 1 after one POST" "${RC}:$(npost)" "1:1"
has "05: and names it" "Not active after 3 seconds: Ftp Default"
STATUS_GET=500 urun 05.servers_wait.sh ftp 3
expect "05: servers that cannot be read: exit 1" "${RC}" "1"
has "05: says so" "Could not read the servers: HTTP 500"
# with a copy of the start, a server that was not active then is not waited for
save_start
RULES="${RUNNING_RULES}" urun 05.servers_wait.sh as2 3
expect "05: a server that was not active at the start is not waited for: exit 0, no POST" "${RC}:$(npost)" "0:0"
has "05: and says there is nothing to wait for" "No as2 server was active at the start: there is nothing to wait for."
RULES="$(rules "/servers" "${S_OFF}")" POST_BODY="${SRV_OK}" urun 05.servers_wait.sh ftp 3
expect "05: with a copy, a server that was active and is not is waited for, then started: one POST" "$(npost)" "1"
clear_state

echo "=== 06 compare ==="
clear_state
RULES="${RUNNING_RULES}" urun 06.compare_with_start.sh
expect "06: with no copy of the start: exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
has "06: says to run 01 first" "run 01.daemons_GET.sh first"
urun 06.compare_with_start.sh extra
expect "06: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
save_start
RULES="${RUNNING_RULES}" urun 06.compare_with_start.sh
expect "06: reads the daemons and the servers again" "$(calls)" "GET ${BASE}/myself${NL}GET ${BASE}/daemons${NL}GET ${BASE}/servers?fields=serverName,isActive&limit=1000"
has "06: nothing different is said, and it is the proof" "Nothing is different: every daemon and every server is as at the start."
expect "06: exit 0" "${RC}" "0"
RULES="$(rules "/daemons" "${D_DOWN}" "/servers" "${S_ACT}")" urun 06.compare_with_start.sh
expect "06: a daemon that is not as at the start is exit 1" "${RC}" "1"
has "06: names the daemon and both statuses" "DIFFERENT: the ftp daemon was Running and is Not running"
has "06: counts the differences" "1 difference(s) from the start."
hasnt "06: and does not say everything is as it was" "Nothing is different"
RULES="$(rules "/daemons" "${D_SSHDOWN}" "/servers" "${S_OFF}")" urun 06.compare_with_start.sh
expect "06: two differences: a daemon and a server" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'DIFFERENT')" "1:2"
has "06: names the server and both states" "DIFFERENT: the server Ftp Default was active and is not active"
has "06: counts them" "2 difference(s) from the start."
RULES="$(rules "/daemons" "${D_RUN}" "/servers" "${S_NEW}")" urun 06.compare_with_start.sh
expect "06: a server that was not there is a difference" "${RC}" "1"
has "06: names it" "DIFFERENT: the server Ftp Extra was not there and is now"
RULES="$(rules "/daemons" "${D_RUN}" "/servers" "${S_GONE}")" urun 06.compare_with_start.sh
expect "06: a server that is gone is a difference" "${RC}" "1"
has "06: names it" "DIFFERENT: the server Ftp Default was active and is gone"
RULES="$(rules "/daemons" "${D_RUN}")" STUB_STATUS_GET_SEQ="200 200 500" STUB_COUNTER="${WORK}/ctr06" urun 06.compare_with_start.sh
expect "06: a servers answer that is not 200 is exit 1" "${RC}" "1"
has "06: says so" "Could not read the servers: HTTP 500"
STATUS_GET=500 urun 06.compare_with_start.sh
expect "06: a daemons answer that is not 200 is exit 1" "${RC}" "1"
has "06: says which call" "GET /daemons: HTTP 500"
clear_state

echo "=== 99 cleanup ==="
clear_state
urun 99.cleanup_DELETE.sh as2
expect "99: as2 is refused: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "99: and says it is never started" "The as2 daemon is never started by this use case."
urun 99.cleanup_DELETE.sh nope
expect "99: a daemon that does not exist: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
urun 99.cleanup_DELETE.sh ftp extra
expect "99: two parameters: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
# no copy of the start: nothing is put back
RULES="$(rules "/daemons" "${D_DOWN}")" POST_BODY="${OK_START}" urun 99.cleanup_DELETE.sh
expect "99: with no copy of the start, nothing is started: no POST but the logout is a DELETE, exit 0" "${RC}:$(npost):$(calls | grep -c '^DELETE ')" "0:0:1"
has "99: says so" "There is no saved copy of the start: nothing is put back."
# everything as at the start
save_start
RULES="${RUNNING_RULES}" urun 99.cleanup_DELETE.sh
expect "99: with all as at the start, nothing is started: no POST" "${RC}:$(npost)" "0:0"
has "99: says so" "The ftp daemon is as it was at the start (Running): nothing to put back."
has "99: the servers were waited for" "The ftp servers (Ftp Default) are active"
expect "99: the session is ended with a DELETE of /myself" "$(calls | grep -c "^DELETE ${BASE}/myself$")" "1"
expect "99: the copy of the start is removed" "$(ls "${UC}"/state.local.daemons.json "${UC}"/state.local.servers.json 2>/dev/null | wc -l | tr -d ' ')" "0"
expect "99: and the session jar and the token" "$(ls "${UC}/session.cookie.jar" "${UC}/state.local.csrf" 2>/dev/null | wc -l | tr -d ' ')" "0"
has "99: ends with Cleaned up." "Cleaned up."
RULES="${RUNNING_RULES}" urun 99.cleanup_DELETE.sh
expect "99: a second time finds nothing to put back and exits 0" "${RC}" "0"
has "99: and says there is no copy" "There is no saved copy of the start"
# the daemon was left stopped: it is started, and waited for
save_start
STUB_CURL_GET_SEQUENCE="$(mkseq c1 "${WORK}/me.json" "${D_DOWN}" "${D_RUN}" "${S_ACT}")" POST_BODY="${OK_START}" urun 99.cleanup_DELETE.sh
expect "99: a daemon that was Running at the start and is not is started: one POST, exit 0" "${RC}:$(npost)" "0:1"
expect "99: the POST starts the ftp daemon" "$(calls | grep -c '^POST .*/daemons/operations?operation=start&daemon=ftp$')" "1"
expect "99: with the csrfToken" "$(hdrs_of POST | grep -c '^csrfToken: tok123$')" "1"
has "99: says what it found" "The ftp daemon was Running at the start and is: Not running. Starting it..."
has "99: waits for it" "The ftp daemon says Running"
expect "99: the copy is removed when all is back" "$(ls "${UC}"/state.local.daemons.json 2>/dev/null | wc -l | tr -d ' ')" "0"
# the start is not accepted (a stop still in progress): one more try after a wait
save_start
STUB_CURL_GET_SEQUENCE="$(mkseq c2 "${WORK}/me.json" "${D_DOWN}" $(rep 6 "${D_DOWN}") "${D_RUN}" "${S_ACT}")" POST_BODY="${NO_START}" urun 99.cleanup_DELETE.sh
expect "99: a start that is not accepted is tried once more: two POSTs" "$(npost)" "2"
has "99: says it is trying again" "trying once more"
# the daemon does not come back
save_start
STUB_CURL_GET_SEQUENCE="$(mkseq c3 "${WORK}/me.json" "${D_DOWN}")" POST_BODY="${OK_START}" urun 99.cleanup_DELETE.sh
expect "99: a daemon that does not come back is exit 1" "${RC}" "1"
has "99: says how long it waited" "is not 'Running' after 120 seconds"
has "99: and says the copy is kept" "the saved copy is kept"
expect "99: the copy is still there, to run it again" "$(ls "${UC}"/state.local.daemons.json "${UC}"/state.local.servers.json 2>/dev/null | wc -l | tr -d ' ')" "2"
expect "99: the session is still ended" "$(ls "${UC}/session.cookie.jar" 2>/dev/null | wc -l | tr -d ' ')" "0"
clear_state
# the daemon is back and a server is not: it is started
save_start
STUB_CURL_GET_SEQUENCE="$(mkseq c4 "${WORK}/me.json" "${D_RUN}" $(rep 42 "${S_OFF}") "${S_ACT}")" POST_BODY="${SRV_OK}" urun 99.cleanup_DELETE.sh
expect "99: a server that was active and is not is started with POST /servers/operations: one POST, exit 0" "${RC}:$(npost)" "0:1"
expect "99: for that server" "$(calls | grep -c '^POST .*/servers/operations?serverName=Ftp Default&operation=start$')" "1"
# the server stays down
save_start
RULES="$(rules "/daemons" "${D_RUN}" "/servers" "${S_OFF}")" POST_BODY="${SRV_OK}" urun 99.cleanup_DELETE.sh
expect "99: a server that stays down is exit 1" "${RC}" "1"
has "99: and says the copy is kept" "the saved copy is kept"
clear_state
# a daemon that was not running at the start is left alone
RULES="$(rules "/daemons" "${D_DOWN}" "/servers" "${S_ACT}")" urun 01.daemons_GET.sh
RULES="$(rules "/daemons" "${D_DOWN}" "/servers" "${S_OFF}")" POST_BODY="${OK_START}" urun 99.cleanup_DELETE.sh
expect "99: a daemon that was not running at the start is not started: no POST, exit 0" "${RC}:$(npost)" "0:0"
clear_state

echo "=== 00 run_all ==="
clear_state
run 00.run_all.sh a b
expect "00: two parameters is exit 2, nothing sent, no cleanup" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c '99.cleanup')" "2:0:0"
has "00: with the usage" "Usage: ./00.run_all.sh [DAEMON]"
run 00.run_all.sh as2
expect "00: the as2 daemon is refused: exit 2, nothing sent, no cleanup" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c '99.cleanup')" "2:0:0"
run 00.run_all.sh nope
expect "00: a daemon that does not exist is refused the same way" "${RC}:$(ncalls)" "2:0"
# the whole run: the Nth GET is answered with the Nth file (each step first reads /myself, to check the session)
FULL="$(mkseq full "${WORK}/me.json" "${D_RUN}" "${S_ACT}" \
    "${WORK}/me.json" "${D_RUN}" \
    "${WORK}/me.json" "${D_DOWN}" \
    "${WORK}/me.json" "${D_DOWN}" \
    "${WORK}/me.json" "${D_RUN}" \
    "${WORK}/me.json" "${S_ACT}" \
    "${WORK}/me.json" "${D_RUN}" "${S_ACT}" \
    "${WORK}/me.json" "${D_RUN}" "${S_ACT}")"
touch "${UC}/session.cookie.jar"
STUB_CURL_GET_SEQUENCE="${FULL}" POST_BODY="${OK_STOP}" run 00.run_all.sh
expect "00: the whole run, 01 to 06 and the cleanup, exits 0" "${RC}" "0"
for s in 01.daemons_GET 02.daemon_stop 03.daemon_wait 04.daemon_start 05.servers_wait 06.compare_with_start 99.cleanup_DELETE; do
    has "00: runs ${s}" "=== ${s} ==="
done
expect "00: one stop and one start, in that order" "$(calls | grep '/daemons/operations' | sed 's/.*operation=\([a-z]*\)&.*/\1/' | tr '\n' ' ')" "stop start "
expect "00: the stop is graceful true" "$(calls | grep -c 'operation=stop&daemon=ftp&graceful=true$')" "1"
has "00: the wait for the stop and for the start" "The ftp daemon says Not running"
has "00: the wait for the servers" "The ftp servers (Ftp Default) are active"
has "00: the proof" "Nothing is different: every daemon and every server is as at the start."
has "00: ends with the cleanup" "Cleaned up."
expect "00: and leaves no state" "$(ls "${UC}"/state.local.daemons.json "${UC}/session.cookie.jar" 2>/dev/null | wc -l | tr -d ' ')" "0"
clear_state
# a step that fails stops the run, and the cleanup still runs
touch "${UC}/session.cookie.jar"
RULES="${RUNNING_RULES}" POST_BODY="${NO_STOP}" run 00.run_all.sh ftp
expect "00: a stop that is not successful stops the run: exit 1" "${RC}" "1"
has "00: names the step" "02.daemon_stop failed."
expect "00: no step after 02 ran" "$(printf '%s\n' "${OUT}" | grep -c '^=== 0[3-6]')" "0"
has "00: and the cleanup still runs" "=== 99.cleanup_DELETE ==="
expect "00: and leaves no state" "$(ls "${UC}"/state.local.daemons.json "${UC}/session.cookie.jar" 2>/dev/null | wc -l | tr -d ' ')" "0"
clear_state
# a step 06 that finds a difference
touch "${UC}/session.cookie.jar"
STUB_CURL_GET_SEQUENCE="$(mkseq fail06 "${WORK}/me.json" "${D_RUN}" "${S_ACT}" "${WORK}/me.json" "${D_RUN}" "${WORK}/me.json" "${D_DOWN}" "${WORK}/me.json" "${D_DOWN}" "${WORK}/me.json" "${D_RUN}" "${WORK}/me.json" "${S_ACT}" "${WORK}/me.json" "${D_SSHDOWN}" "${S_ACT}" "${WORK}/me.json" "${D_RUN}" "${S_ACT}")" POST_BODY="${OK_STOP}" run 00.run_all.sh
expect "00: a difference found by 06 is exit 1" "${RC}" "1"
has "00: names the step" "06.compare_with_start failed."
has "00: and the cleanup still runs" "=== 99.cleanup_DELETE ==="
clear_state

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}/04-stopping-and-starting-servers"/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/API 2.0\/bash\/[^ ,]*).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "$(dirname "${s}")")/$(basename "${s}")"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_04: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_04: PASS"
