#!/bin/bash
# ==============================================================================
# Run the older Admin write examples that were brought up to the house rules
# (sweep A) against a stub curl, and check what each one does: that it
# validates its arguments and sends nothing when they are wrong (exit 2), builds
# every body with jq, encodes names in URLs, prints the HTTP code that curl
# itself reports (-w), and exits 1 when the server refuses a call.
#
#   03.Connect          07 servers_POST, 10 servers_name_PUT, 11 servers_name_PATCH,
#                       12 servers_name_DELETE, 13 servers_operations_POST
#   06.TransferSites    01 sites_POST, 02 sites_POST_ssh, 04 sites_id_DELETE
#   07.Subscriptions    02, 03, 04, 12, 13
#   08.RouteTemplates   02 routes_POST, 03 routes_DELETE_all
#   09.CompositeRoutes  03, 04, 07
#
# The stub answers one status for every call, so a wrapper in front of it
# (SWEEP_SEQ) gives each call of one run its own status and body, and can put a
# "100 Continue" block in front of a headers file (SWEEP_CONTINUE), as a server
# does: the older scripts read the status from the first line of that file.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
ADMIN_TREE="${REPO}/Admin/API 2.0/bash"
BAT_TREE="${REPO}/Admin/API 2.0/bat"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_sweep_a"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin" "${WORK}/seq"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

# The stub, behind a wrapper that can answer each call of a run differently
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl_stub" && chmod +x "${WORK}/bin/curl_stub"
cat > "${WORK}/bin/curl" <<'WRAPPER'
#!/bin/bash
# SWEEP_SEQ: a file with one line per curl call, STATUS or STATUS<TAB>BODY_FILE; the last line repeats.
# SWEEP_CONTINUE: put "HTTP/1.1 100 Continue" in front of the headers file (-D) the stub writes.
if [ -n "${SWEEP_SEQ}" ] && [ -f "${SWEEP_SEQ}" ]; then
    n=$(( $(cat "${SWEEP_SEQ}.n" 2>/dev/null || echo 0) + 1 ))
    echo "${n}" > "${SWEEP_SEQ}.n"
    total=$(grep -c '' "${SWEEP_SEQ}")
    if [ "${n}" -gt "${total}" ]; then n="${total}"; fi
    IFS=$'\t' read -r status bodyfile < <(sed -n "${n}p" "${SWEEP_SEQ}")
    export STUB_CURL_STATUS="${status}" STUB_CURL_STATUS_GET=""
    if [ -n "${bodyfile}" ]; then
        export STUB_CURL_GET_BODY="${bodyfile}" STUB_CURL_POST_BODY="${bodyfile}" STUB_CURL_GET_SEQUENCE="" STUB_CURL_GET_RULES=""
    fi
fi
# the stub serves a body for GET and POST only: a PUT, PATCH or DELETE gets its body here, in front of the -w text
if [ -n "${bodyfile}" ]; then
    prev=""
    for a in "$@"; do
        if [ "${prev}" = "-X" ] && [ "${a}" != "GET" ] && [ "${a}" != "POST" ]; then cat "${bodyfile}"; fi
        prev="${a}"
    done
fi
"$(dirname "$0")/curl_stub" "$@"
rc=$?
if [ -n "${SWEEP_CONTINUE}" ]; then
    prev=""
    for a in "$@"; do
        if [ "${prev}" = "-D" ]; then headers="${a}"; fi
        prev="${a}"
    done
    if [ -n "${headers}" ] && [ -f "${headers}" ]; then
        { printf 'HTTP/1.1 100 Continue\r\n\r\n'; cat "${headers}"; } > "${headers}.sweep" && mv "${headers}.sweep" "${headers}"
    fi
fi
exit "${rc}"
WRAPPER
chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
BASE="https://st.example.com:8444/api/v2.0"

# body NAME JSON: a canned answer, in a file
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
# seq NAME LINE...: a SWEEP_SEQ file; a line is STATUS, or STATUS and a body file (as "STATUS<TAB>FILE" in one argument, use sl)
seq() {
    local file="${WORK}/seq/$1"
    shift
    : > "${file}"
    for line in "$@"; do printf '%s\n' "${line}" >> "${file}"; done
    echo "${file}"
}
# sl STATUS FILE: one line of a seq with a body
sl() { printf '%s\t%s' "$1" "$2"; }
# run FOLDER/SCRIPT ARGS...: GET_BODY, POST_BODY, LOCATION, STATUS, STATUS_GET, RULES, SWEEP_SEQ and SWEEP_CONTINUE set the answers
run() {
    local rel="$1"; shift
    mkdir -p "${WORK}/admin/$(dirname "${rel}")"
    cp "${ADMIN_TREE}/${rel}" "${WORK}/admin/${rel}"
    rm -f "${SWEEP_SEQ:-/nonexistent}.n"
    OUT=$(cd "${WORK}/admin/$(dirname "${rel}")" && PATH="${WORK}/bin:${PATH}" \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" \
          STUB_CURL_LOCATION_ID="${LOCATION:-}" STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" \
          STUB_CURL_PRINT_CODE=1 SWEEP_SEQ="${SWEEP_SEQ:-}" SWEEP_CONTINUE="${SWEEP_CONTINUE:-}" \
          bash "./$(basename "${rel}")" "$@" 2>&1)
    RC=$?
}
# reset: the answers of one test do not leak into the next
reset() { GET_BODY= POST_BODY= LOCATION= STATUS= STATUS_GET= RULES= SWEEP_SEQ= SWEEP_CONTINUE=; }
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | grep -c .; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
# bad_args LABEL: exit 2 and not one call
bad_args() { expect "$1" "${RC}:$(ncalls)" "2:0"; }

# ------------------------------------------------------------------------------
# The bodies the tests answer with
# ------------------------------------------------------------------------------
SSH_SERVER='{"serverName":"SSH_TEST_SERVER_1","protocol":"ssh","port":8022,"isActive":false,"clientPasswordAuth":"default","ciphers":"aes128-ctr","publicKeys":"ssh-rsa,x509v3-rsa2048-sha256,rsa-sha2-256,ecdsa-sha2-nistp256,ssh-ed25519","advanced":{"port":9999}}'
SSH_SERVER_NO_RSA='{"serverName":"SSH_TEST_SERVER_1","protocol":"ssh","port":8022,"publicKeys":"ecdsa-sha2-nistp256,ssh-ed25519"}'
HTTP_SERVER='{"serverName":"SSH_TEST_SERVER_1","protocol":"http","port":8080}'
REFUSED='{"message":"Error validating request","validationErrors":["Server with name SSH_TEST_SERVER_1 already exist."],"docLink":"x"}'

# ==============================================================================
echo "=== 03.Connect/07.servers_POST.sh ==="
F=03.Connect
S="${BASE}/servers"
reset
SWEEP_SEQ=$(seq s07 201 "$(sl 200 "$(body ssh_server "${SSH_SERVER}")")" 201) run "${F}/07.servers_POST.sh"
expect "07 POST: creates a minimal server, reads it, creates the duplicate; exit 0" "${RC}:$(calls)" "0:POST ${S}
GET ${S}/SSH_TEST_SERVER_1
POST ${S}"
expect "07 POST: the minimal body is built by jq: name and protocol only" "$(payload 1 | jq -c .)" '{"serverName":"SSH_TEST_SERVER_1","protocol":"ssh"}'
expect "07 POST: the duplicate is the object read, with the name, the port and clientPasswordAuth changed and the rest kept" \
  "$(payload 2 | jq -c '[.serverName, .port, (.port | type), .clientPasswordAuth, .advanced, .ciphers, .publicKeys == "ssh-rsa,x509v3-rsa2048-sha256,rsa-sha2-256,ecdsa-sha2-nistp256,ssh-ed25519"]')" \
  '["SSH_TEST_SERVER_2",8030,"number","default",{"port":9999},"aes128-ctr",true]'
expect "07 POST: prints the code of both creations" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 201$')" "2"
hasnt "07 POST: leaves no tmp.json behind" "tmp.json"
expect "07 POST: no tmp.json in the folder" "$(ls "${WORK}/admin/${F}" | grep -c '^tmp.json')" "0"

SWEEP_SEQ=$(seq s07b 201 "$(sl 200 "${WORK}/ssh_server.json")" 201) run "${F}/07.servers_POST.sh" "Ssh Default" "Other \"Server\"" 9000
expect "07 POST: names and port given; a name with a space is encoded in the URL" "${RC}:$(calls | sed -n 2p)" "0:GET ${S}/Ssh%20Default"
expect "07 POST: the first body holds the name given, quotes kept" "$(payload 1 | jq -r .serverName)" "Ssh Default"
expect "07 POST: the second holds the new name, a quote in it intact, and the port given" "$(payload 2 | jq -c '[.serverName, .port]')" '["Other \"Server\"",9000]'

SWEEP_SEQ=$(seq s07c "$(sl 409 "$(body refused "${REFUSED}")")") run "${F}/07.servers_POST.sh"
expect "07 POST: a refused first creation exits 1 and stops there" "${RC}:$(ncalls)" "1:1"
has "07 POST: shows the code" "HTTP 409"
has "07 POST: and the server's message" "Server with name SSH_TEST_SERVER_1 already exist."
SWEEP_SEQ=$(seq s07d 201 "$(sl 404 "${WORK}/refused.json")") run "${F}/07.servers_POST.sh"
expect "07 POST: a read that fails exits 1, and the duplicate is not sent" "${RC}:$(calls | grep -c '^POST')" "1:1"
SWEEP_SEQ=$(seq s07e 201 "$(sl 200 "${WORK}/ssh_server.json")" "$(sl 400 "${WORK}/refused.json")") run "${F}/07.servers_POST.sh"
expect "07 POST: a refused duplicate exits 1" "${RC}" "1"
reset
run "${F}/07.servers_POST.sh" a a
bad_args "07 POST: the same name twice, exit 2, nothing sent"
for port in 0 65536 abc -1 8022x; do
    run "${F}/07.servers_POST.sh" a b "${port}"
    bad_args "07 POST: port '${port}' is refused, nothing sent"
done
run "${F}/07.servers_POST.sh" a b 8000 extra
bad_args "07 POST: a fourth argument, nothing sent"

# ==============================================================================
echo
echo "=== 03.Connect/10.servers_name_PUT.sh ==="
SSH_FILE=$(body ssh_server "${SSH_SERVER}")
SWEEP_SEQ=$(seq s10 "$(sl 200 "${SSH_FILE}")" 204 "$(sl 200 "${SSH_FILE}")" 204) run "${F}/10.servers_name_PUT.sh"
expect "10 PUT: reads the server, PUTs a fragment, reads again, PUTs the whole object; exit 0" "${RC}:$(calls)" "0:GET ${S}/SSH_TEST_SERVER_1
PUT ${S}/SSH_TEST_SERVER_1
GET ${S}/SSH_TEST_SERVER_1
PUT ${S}/SSH_TEST_SERVER_1"
expect "10 PUT: the fragment is built by jq: name, protocol, and the port as a number" "$(payload 1 | jq -c .)" '{"serverName":"SSH_TEST_SERVER_1","protocol":"ssh","port":8031}'
expect "10 PUT: the whole object is the one read, with the port and clientPasswordAuth set" "$(payload 2 | jq -c '[.port, .clientPasswordAuth, .advanced, .ciphers]')" '[8031,"default",{"port":9999},"aes128-ctr"]'
has "10 PUT: prints the port the server had" "The port of SSH_TEST_SERVER_1 is now 8022"
expect "10 PUT: prints the code of both PUTs" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 204$')" "2"
SWEEP_SEQ=$(seq s10b "$(sl 200 "${SSH_FILE}")" 204 "$(sl 200 "${SSH_FILE}")" 204) run "${F}/10.servers_name_PUT.sh" "Ssh Default" 9100
expect "10 PUT: a name with a space is encoded, and the port is the one given" "${RC}:$(calls | sed -n 1p):$(payload 1 | jq -c '[.serverName, .port]')" "0:GET ${S}/Ssh%20Default:[\"Ssh Default\",9100]"
SWEEP_SEQ=$(seq s10c "$(sl 200 "$(body http_server "${HTTP_SERVER}")")") run "${F}/10.servers_name_PUT.sh"
expect "10 PUT: a server of another protocol is not touched: exit 1, no PUT" "${RC}:$(calls | grep -c '^PUT')" "1:0"
SWEEP_SEQ=$(seq s10d "$(sl 404 "${WORK}/refused.json")") run "${F}/10.servers_name_PUT.sh"
expect "10 PUT: a server that cannot be read: exit 1, no PUT" "${RC}:$(calls | grep -c '^PUT')" "1:0"
has "10 PUT: says why" "Could not read the server SSH_TEST_SERVER_1: HTTP 404"
SWEEP_SEQ=$(seq s10e "$(sl 200 "${SSH_FILE}")" "$(sl 400 "${WORK}/refused.json")") run "${F}/10.servers_name_PUT.sh"
expect "10 PUT: a refused PUT exits 1 and stops" "${RC}:$(calls | grep -c '^PUT')" "1:1"
has "10 PUT: with the server's message" "already exist."
reset
for port in 0 65536 abc; do
    run "${F}/10.servers_name_PUT.sh" a "${port}"
    bad_args "10 PUT: port '${port}' is refused, nothing sent"
done
run "${F}/10.servers_name_PUT.sh" a 8000 extra
bad_args "10 PUT: a third argument, nothing sent"

# ==============================================================================
echo
echo "=== 03.Connect/11.servers_name_PATCH.sh ==="
SWEEP_SEQ=$(seq s11 "$(sl 200 "${SSH_FILE}")" 204 204 "$(sl 200 "${SSH_FILE}")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: reads, patches the port, patches the keys, reads; exit 0" "${RC}:$(calls)" "0:GET ${S}/SSH_TEST_SERVER_1
PATCH ${S}/SSH_TEST_SERVER_1
PATCH ${S}/SSH_TEST_SERVER_1
GET ${S}/SSH_TEST_SERVER_1"
expect "11 PATCH: the port patch is an ARRAY of one operation, not an object" "$(payload 1 | jq -c '[type, .]')" '["array",[{"op":"replace","path":"/port","value":8026}]]'
expect "11 PATCH: the keys patch is an array too, with every key that has rsa in it removed (read with jq, not grep)" \
  "$(payload 2 | jq -c '[type, .]')" '["array",[{"op":"replace","path":"/publicKeys","value":"ecdsa-sha2-nistp256,ssh-ed25519"}]]'
has "11 PATCH: shows the keys before" "Public keys before removing rsa: ssh-rsa,x509v3-rsa2048-sha256,rsa-sha2-256,ecdsa-sha2-nistp256,ssh-ed25519"
has "11 PATCH: and after" "Public keys after removal: ecdsa-sha2-nistp256,ssh-ed25519"
expect "11 PATCH: prints the code of both patches" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 204$')" "2"
SWEEP_SEQ=$(seq s11b "$(sl 200 "${SSH_FILE}")" 204 204 "$(sl 200 "${SSH_FILE}")") run "${F}/11.servers_name_PATCH.sh" "Ssh Default" 9200
expect "11 PATCH: a name with a space is encoded; the port given is sent as a number" "${RC}:$(calls | sed -n 2p):$(payload 1 | jq -c '.[0].value')" "0:PATCH ${S}/Ssh%20Default:9200"
SWEEP_SEQ=$(seq s11c "$(sl 200 "$(body ssh_no_rsa "${SSH_SERVER_NO_RSA}")")" 204 "$(sl 200 "${WORK}/ssh_no_rsa.json")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: no rsa key to remove: only the port is patched" "${RC}:$(calls | grep -c '^PATCH')" "0:1"
has "11 PATCH: and it says so" "There is no rsa key to remove"
ODD='{"serverName":"SSH_TEST_SERVER_1","protocol":"ssh","port":8022,"publicKeys":"x\"y\\z,ssh-rsa,keep-this"}'
SWEEP_SEQ=$(seq s11d "$(sl 200 "$(body ssh_odd "${ODD}")")" 204 204 "$(sl 200 "${WORK}/ssh_odd.json")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: a quote and a backslash in a key name stay valid JSON, unchanged" "$(payload 2 | jq -r '.[0].value')" 'x"y\z,keep-this'
SWEEP_SEQ=$(seq s11e "$(sl 200 "${WORK}/http_server.json")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: a server of another protocol is not touched: exit 1, no PATCH" "${RC}:$(calls | grep -c '^PATCH')" "1:0"
SWEEP_SEQ=$(seq s11f "$(sl 200 "${SSH_FILE}")" "$(sl 400 "$(body bad_port '{"message":"Error validating request","validationErrors":["mPort must be less than or equal to 65535"]}')")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: a refused port patch exits 1, and the keys are not patched" "${RC}:$(calls | grep -c '^PATCH')" "1:1"
has "11 PATCH: with the server's message" "mPort must be less than or equal to 65535"
SWEEP_SEQ=$(seq s11g "$(sl 200 "${SSH_FILE}")" 204 "$(sl 400 "${WORK}/refused.json")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: a refused keys patch exits 1" "${RC}" "1"
SWEEP_SEQ=$(seq s11h "$(sl 404 "${WORK}/refused.json")") run "${F}/11.servers_name_PATCH.sh"
expect "11 PATCH: a server that cannot be read: exit 1, nothing patched" "${RC}:$(calls | grep -c '^PATCH')" "1:0"
reset
for port in 0 65536 abc; do
    run "${F}/11.servers_name_PATCH.sh" a "${port}"
    bad_args "11 PATCH: port '${port}' is refused, nothing sent"
done
run "${F}/11.servers_name_PATCH.sh" a 8000 extra
bad_args "11 PATCH: a third argument, nothing sent"
# the bat twin: the old one piped a one-element array into ConvertTo-Json, which sends an object
BAT11="${BAT_TREE}/03.Connect/11.servers_name_PATCH.bat"
expect "11 PATCH (bat): builds both patches with ConvertTo-Json -InputObject, which keeps the array" "$(grep -vE '^REM' "${BAT11}" | grep -c 'ConvertTo-Json -InputObject')" "2"
expect "11 PATCH (bat): never pipes an array into ConvertTo-Json for a patch" "$(grep -cE '@\(\$patch\) \| ConvertTo-Json|\) \| ConvertTo-Json.*op *=' "${BAT11}")" "0"
expect "11 PATCH (bat): no grep, awk or sed in it" "$(grep -vE '^REM' "${BAT11}" | grep -ciE '\b(grep|awk|sed)\b')" "0"

# ==============================================================================
echo
echo "=== 03.Connect/12.servers_name_DELETE.sh ==="
SWEEP_SEQ=$(seq s12 200 204 200 204) run "${F}/12.servers_name_DELETE.sh"
expect "12 DELETE: HEAD then DELETE for each of the two test servers; exit 0" "${RC}:$(calls)" "0:HEAD ${S}/SSH_TEST_SERVER_1
DELETE ${S}/SSH_TEST_SERVER_1
HEAD ${S}/SSH_TEST_SERVER_2
DELETE ${S}/SSH_TEST_SERVER_2"
has "12 DELETE: prints the code" "HTTP 204"
has "12 DELETE: and what it deleted" "Deleted 'SSH_TEST_SERVER_1'."
SWEEP_SEQ=$(seq s12b 200 204) run "${F}/12.servers_name_DELETE.sh" "My Server"
expect "12 DELETE: a name given replaces the defaults, and is encoded" "${RC}:$(calls)" "0:HEAD ${S}/My%20Server
DELETE ${S}/My%20Server"
SWEEP_SEQ=$(seq s12c 200 204 200 204) run "${F}/12.servers_name_DELETE.sh" one two
expect "12 DELETE: several names, each in turn" "$(calls | grep -c '^DELETE')" "2"
SWEEP_SEQ=$(seq s12d 400 400) run "${F}/12.servers_name_DELETE.sh"
expect "12 DELETE: a HEAD of 400 (what an unknown server answers) is 'does not exist': no DELETE, exit 0" "${RC}:$(calls | grep -c '^DELETE')" "0:0"
has "12 DELETE: says so" "The server 'SSH_TEST_SERVER_1' does not exist"
SWEEP_SEQ=$(seq s12e 200 "$(sl 400 "${WORK}/refused.json")" 200 204) run "${F}/12.servers_name_DELETE.sh"
expect "12 DELETE: a refused DELETE exits 1, the next server is still tried" "${RC}:$(calls | grep -c '^DELETE')" "1:2"
has "12 DELETE: shows the code and the message" "HTTP 400"
SWEEP_SEQ=$(seq s12f 500) run "${F}/12.servers_name_DELETE.sh" one
expect "12 DELETE: a HEAD that is neither 200 nor 'not there' exits 1 and deletes nothing" "${RC}:$(calls | grep -c '^DELETE')" "1:0"
reset
run "${F}/12.servers_name_DELETE.sh" one ""
bad_args "12 DELETE: an empty name, exit 2, nothing sent (not even for the first)"

# ==============================================================================
echo
echo "=== 03.Connect/13.servers_operations_POST.sh (disruptive: guarded, offline only) ==="
G="${S}/operations"
SERVER_LIST_OFF='{"resultSet":{"returnCount":2},"result":[{"protocol":"ssh","serverName":"Ssh Default","isActive":false},{"protocol":"ftp","serverName":"Ftp Default","isActive":true}]}'
SERVER_LIST_ON='{"resultSet":{"returnCount":2},"result":[{"protocol":"ssh","serverName":"Ssh Default","isActive":true},{"protocol":"ftp","serverName":"Ftp Default","isActive":true}]}'
DAEMONS_UP='{"ftpStatus":"Running","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Running","as2Status":"Not running"}'
DAEMONS_SSH_DOWN='{"ftpStatus":"Running","sshStatus":"Not running"}'
OP_OK='{"serverStatuses":[{"serverName":"Ssh Default","message":"Server started successfully.","isSuccessful":true}]}'
OP_NO='{"serverStatuses":[{"serverName":"Ssh Default","message":"the ssh daemon is not started","isSuccessful":false}]}'
reset
run "${F}/13.servers_operations_POST.sh"
bad_args "13: bare (it used to start everything), exit 2, nothing sent"
has "13: bare prints the usage" "Usage: 13.servers_operations_POST.sh SERVER start"
run "${F}/13.servers_operations_POST.sh" "Ssh Default"
bad_args "13: a server and no operation, nothing sent"
run "${F}/13.servers_operations_POST.sh" "Ssh Default" restart
bad_args "13: an operation that is not start or stop, nothing sent"
run "${F}/13.servers_operations_POST.sh" "Ssh Default" start now
bad_args "13: a start with an extra argument, nothing sent"
run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop
bad_args "13: a stop with no confirmation, nothing sent"
has "13: a stop without it says which word to give, with the name in it" "stop-the-Ssh Default-server"
for word in yes stop-the-ssh-server "stop-the-Ssh Default" "stop-the-Other-server" ""; do
    run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "${word}"
    bad_args "13: a stop with the word '${word}', nothing sent"
done
run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server" abc
bad_args "13: a timeout that is not a number, nothing sent"
run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server" 200 more
bad_args "13: too many arguments to a stop, nothing sent"
run "${F}/13.servers_operations_POST.sh" ""  start
bad_args "13: an empty server name, nothing sent"
run "${F}/13.servers_operations_POST.sh" --all-stopped
bad_args "13: --all-stopped alone, nothing sent"
has "13: and it says that it starts what was stopped on purpose" "including those an administrator stopped on purpose"
run "${F}/13.servers_operations_POST.sh" --all-stopped yes
bad_args "13: --all-stopped with another word, nothing sent"
run "${F}/13.servers_operations_POST.sh" --all-stopped start-all-stopped-servers more
bad_args "13: --all-stopped with an extra argument, nothing sent"
# the confirmation word is not in the environment either: nothing but arguments sends a stop
STOP_ENV=1 run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop
bad_args "13: no environment variable stands in for the word"

# a start
SWEEP_SEQ=$(seq s13a "$(sl 200 "$(body list_off "${SERVER_LIST_OFF}")")" "$(sl 200 "$(body daemons_up "${DAEMONS_UP}")")" "$(sl 200 "$(body op_ok "${OP_OK}")")") \
  run "${F}/13.servers_operations_POST.sh" "Ssh Default" start
expect "13 start: reads the servers and the daemons, then posts the operation, the name in the query" "${RC}:$(calls)" "0:GET ${S}?fields=serverName,isActive&limit=200&offset=0
GET ${BASE}/daemons
POST ${G}?serverName=Ssh Default&operation=start"
has "13 start: prints the state and the daemon's" "The ssh server 'Ssh Default' is now: not active. Its ssh daemon is: Running"
has "13 start: and how to stop it again" "To stop it again: ./13.servers_operations_POST.sh 'Ssh Default' stop 'stop-the-Ssh Default-server'"
has "13 start: prints the code" "HTTP 200"
has "13 start: and the result" "Ssh Default Server started successfully. (successful: true)"
SWEEP_SEQ=$(seq s13b "$(sl 200 "${WORK}/list_off.json")" "$(sl 200 "$(body daemons_ssh_down "${DAEMONS_SSH_DOWN}")")" "$(sl 200 "${WORK}/op_no.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" start
expect "13 start: a 200 whose result is not successful exits 1" "${RC}" "1"
has "13 start: says the daemon is not running, and which script starts it" "05.daemons_operations_POST.sh ssh start"
SWEEP_SEQ=$(seq s13c "$(sl 200 "${WORK}/list_off.json")" "$(sl 200 "${WORK}/daemons_up.json")" "$(sl 400 "${WORK}/refused.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" start
expect "13 start: a refused operation exits 1" "${RC}" "1"
SWEEP_SEQ=$(seq s13d "$(sl 200 "$(body list_on "${SERVER_LIST_ON}")")" "$(sl 200 "${WORK}/daemons_up.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" start
expect "13 start: a server that is already active: no operation sent, exit 0" "${RC}:$(calls | grep -c '^POST')" "0:0"
SWEEP_SEQ=$(seq s13e "$(sl 200 "${WORK}/list_off.json")" "$(sl 200 "${WORK}/daemons_up.json")") run "${F}/13.servers_operations_POST.sh" "Nothing Here" start
expect "13 start: a server that is not there: exit 1, no operation sent" "${RC}:$(calls | grep -c '^POST')" "1:0"
SWEEP_SEQ=$(seq s13f "$(sl 500 "${WORK}/refused.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" start
expect "13 start: a list that cannot be read: exit 1, nothing else sent" "${RC}:$(ncalls)" "1:1"

# a stop, with the word
SWEEP_SEQ=$(seq s13g "$(sl 200 "${WORK}/list_on.json")" "$(sl 200 "${WORK}/daemons_up.json")" "$(sl 200 "${WORK}/op_ok.json")") \
  run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server" 200
expect "13 stop: with the word, and a timeout, the operation is posted" "${RC}:$(calls | tail -n 1)" "0:POST ${G}?serverName=Ssh Default&operation=stop&timeout=200"
has "13 stop: it prints how to bring the server back first" "To bring it back: ./13.servers_operations_POST.sh 'Ssh Default' start"
SWEEP_SEQ=$(seq s13h "$(sl 200 "${WORK}/list_on.json")" "$(sl 200 "${WORK}/daemons_up.json")" "$(sl 200 "${WORK}/op_ok.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server"
expect "13 stop: no timeout, none is sent" "$(calls | tail -n 1)" "POST ${G}?serverName=Ssh Default&operation=stop"
SWEEP_SEQ=$(seq s13i "$(sl 200 "${WORK}/list_off.json")" "$(sl 200 "${WORK}/daemons_up.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server"
expect "13 stop: a server that is not active has nothing to stop: no operation sent, exit 0" "${RC}:$(calls | grep -c '^POST')" "0:0"
SWEEP_SEQ=$(seq s13j "$(sl 200 "${WORK}/list_on.json")" "$(sl 200 "${WORK}/daemons_up.json")" "$(sl 403 "${WORK}/refused.json")") run "${F}/13.servers_operations_POST.sh" "Ssh Default" stop "stop-the-Ssh Default-server"
expect "13 stop: a refused stop exits 1" "${RC}" "1"

# --all-stopped: the servers that are not running, then the daemons that are not running
OP_FTP_OK='{"serverStatuses":[{"serverName":"Ftp Default","message":"Server started successfully.","isSuccessful":true}]}'
LIST_TWO_OFF='{"result":[{"protocol":"ssh","serverName":"Ssh Default","isActive":false},{"protocol":"ftp","serverName":"Ftp Default","isActive":false},{"protocol":"http","serverName":"Http Default","isActive":true}]}'
DAEMON_AS2_NO='{"daemonOperationResults":[{"daemon":"as2","message":"Can not start AS2 daemon - the default server As2 Default is not enabled.","isSuccessful":false}]}'
SWEEP_SEQ=$(seq s13k "$(sl 200 "$(body list_two_off "${LIST_TWO_OFF}")")" "$(sl 200 "${WORK}/op_ok.json")" "$(sl 200 "$(body op_ftp_ok "${OP_FTP_OK}")")" \
  "$(sl 200 "${WORK}/daemons_up.json")" "$(sl 200 "$(body daemon_as2_no "${DAEMON_AS2_NO}")")") run "${F}/13.servers_operations_POST.sh" --all-stopped start-all-stopped-servers
expect "13 all: starts each server that is not running, then each daemon that is not running (as2), with the names encoded" "$(calls)" "GET ${S}?fields=serverName,isActive&limit=200&offset=0
POST ${G}?serverName=Ssh Default&operation=start
POST ${G}?serverName=Ftp Default&operation=start
GET ${BASE}/daemons
POST ${BASE}/daemons/operations?operation=start&daemon=as2"
expect "13 all: the as2 daemon that cannot start (200 with isSuccessful false) makes it exit 1" "${RC}" "1"
has "13 all: it names the active server as running" "Server: Http Default is running"
has "13 all: and a daemon that is running" "Daemon ssh is Running"
has "13 all: it prints the reason the as2 daemon did not start" "the default server As2 Default is not enabled. (successful: false)"
SWEEP_SEQ=$(seq s13l "$(sl 200 "${WORK}/list_on.json")" "$(sl 200 "$(body daemons_all_up '{"ftpStatus":"Running","httpStatus":"Running","pesitStatus":"Running","sshStatus":"Running","as2Status":"Running"}')")") run "${F}/13.servers_operations_POST.sh" --all-stopped start-all-stopped-servers
expect "13 all: everything running: nothing is posted, exit 0" "${RC}:$(calls | grep -c '^POST')" "0:0"
SWEEP_SEQ=$(seq s13m "$(sl 200 "${WORK}/list_two_off.json")" "$(sl 403 "${WORK}/refused.json")" "$(sl 200 "${WORK}/op_ftp_ok.json")" "$(sl 200 "${WORK}/daemons_all_up.json")") run "${F}/13.servers_operations_POST.sh" --all-stopped start-all-stopped-servers
expect "13 all: a refused start exits 1, and the next server is still tried" "${RC}:$(calls | grep -c '^POST')" "1:2"
reset
# the risk header stays disruptive, in both twins
expect "13: still Risk: disruptive in both twins" "$(grep -c '^# Risk: disruptive' "${ADMIN_TREE}/${F}/13.servers_operations_POST.sh"):$(grep -c '^REM Risk: disruptive' "${BAT_TREE}/${F}/13.servers_operations_POST.bat")" "1:1"

# ==============================================================================
echo
echo "=== 06.TransferSites/01.sites_POST.sh ==="
F=06.TransferSites
SI="${BASE}/sites"
STATUS=201 LOCATION=newsiteid run "${F}/01.sites_POST.sh"
expect "01 POST: one POST of the site, exit 0" "${RC}:$(calls)" "0:POST ${SI}"
expect "01 POST: the HTTP site, built by jq, host from ST_SERVER" "$(payload 1 | jq -cS .)" \
  '{"account":"john","downloadPattern":"*","host":"st.example.com","name":"HTTP","port":"443","protocol":"http","type":"http","uploadFolder":"/","userName":"john"}'
has "01 POST: prints the code" "HTTP 201"
has "01 POST: and the new id from Location" "New site ID: newsiteid"
STATUS=201 LOCATION=newsiteid SWEEP_CONTINUE=1 run "${F}/01.sites_POST.sh"
has "01 POST: with a 100 Continue block before the real status line, it still says 201" "HTTP 201"
hasnt "01 POST: and not 100" "HTTP 100"
STATUS=409 POST_BODY=$(body site_dup '{"message":"Error validating request","validationErrors":["Entry already exist."]}') run "${F}/01.sites_POST.sh"
expect "01 POST: a refused creation exits 1" "${RC}" "1"
has "01 POST: with the code" "HTTP 409"
has "01 POST: and the server's message" "Entry already exist."
reset
run "${F}/01.sites_POST.sh" extra
bad_args "01 POST: an argument is refused, nothing sent"

# ==============================================================================
echo
echo "=== 06.TransferSites/02.sites_POST_ssh.sh ==="
unset PARTNER_PASSWORD
run "${F}/02.sites_POST_ssh.sh"
bad_args "02 ssh: no PARTNER_PASSWORD, exit 2, nothing sent"
has "02 ssh: it says what to set" "PARTNER_PASSWORD must be set"
PARTNER_PASSWORD=change_me run "${F}/02.sites_POST_ssh.sh"
bad_args "02 ssh: the placeholder change_me is refused, nothing sent"
PARTNER_PASSWORD='p "q" \ $x' STATUS=201 LOCATION=siteid run "${F}/02.sites_POST_ssh.sh"
expect "02 ssh: with a password, the pull site and the push site are posted; exit 0" "${RC}:$(calls)" "0:POST ${SI}
POST ${SI}"
expect "02 ssh: the pull site, the password as given (quotes, backslash and dollar kept), the port 8022 as text" \
  "$(payload 1 | jq -c '[.name, .type, .port, .password, .usePassword, .host, .userName, .account, .downloadFolder, .postTransmissionActions]')" \
  '["SSH_PULL","ssh","8022","p \"q\" \\ $x",true,"st.example.com","john","john","/outbound-drop",{"doAsIn":"${stenv.target}_PULLED"}]'
expect "02 ssh: the push site" "$(payload 2 | jq -c '[.name, .port, .uploadFolder, .postTransmissionActions]')" '["SSH_PUSH","8022","/delivered",{"doAsOut":"${stenv.target}_PUSHED"}]'
expect "02 ssh: the secret is never printed" "$(printf '%s\n' "${OUT}" | grep -cF 'p "q"')" "0"
has "02 ssh: prints the code of each" "HTTP 201"
expect "02 ssh: and the id of each" "$(printf '%s\n' "${OUT}" | grep -c 'New site ID: siteid')" "2"
PARTNER_PASSWORD=pw STATUS=201 run "${F}/02.sites_POST_ssh.sh" 2222
expect "02 ssh: a port given is used for both sites, as text" "$(payload 1 | jq -r .port):$(payload 2 | jq -r .port)" "2222:2222"
PARTNER_PASSWORD=pw STATUS=201 SWEEP_CONTINUE=1 run "${F}/02.sites_POST_ssh.sh"
hasnt "02 ssh: a 100 Continue block does not change the code" "HTTP 100"
PARTNER_PASSWORD=pw SWEEP_SEQ=$(seq s02a "$(sl 409 "${WORK}/site_dup.json")" 201) run "${F}/02.sites_POST_ssh.sh"
expect "02 ssh: a refused pull site exits 1, and the push site is still tried" "${RC}:$(calls | grep -c '^POST')" "1:2"
has "02 ssh: with the server's message" "Entry already exist."
for port in 0 65536 abc -22; do
    PARTNER_PASSWORD=pw run "${F}/02.sites_POST_ssh.sh" "${port}"
    bad_args "02 ssh: port '${port}' is refused, nothing sent"
done
PARTNER_PASSWORD=pw run "${F}/02.sites_POST_ssh.sh" 2222 extra
bad_args "02 ssh: two arguments, nothing sent"
expect "02 ssh: no password literal and no change_me default left in the script" "$(grep -vE '^\s*#' "${ADMIN_TREE}/${F}/02.sites_POST_ssh.sh" | grep -c 'change_me:\|:-change_me\|=change_me')" "0"
reset

# ==============================================================================
echo
echo "=== 06.TransferSites/04.sites_id_DELETE.sh ==="
PULL_LIST='{"result":[{"id":"p1","name":"SSH_PULL"},{"id":"p9","name":"SSH_PULL2"},{"id":"p8","name":"ssh_pull"}]}'
PUSH_LIST='{"result":[{"id":"u1","name":"SSH_PUSH"}]}'
HTTP_LIST='{"result":[{"id":"h1","name":"HTTP"}]}'
NONE='{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}'
LK="${SI}?account=john&name="
SWEEP_SEQ=$(seq s04 "$(sl 200 "$(body pull_list "${PULL_LIST}")")" 204 "$(sl 200 "$(body push_list "${PUSH_LIST}")")" 204 "$(sl 200 "$(body none "${NONE}")")") run "${F}/04.sites_id_DELETE.sh"
expect "04 DELETE: looks SSH_PULL, SSH_PUSH and HTTP up by account and name (encoded, with the name field), deletes the exact matches by id" "${RC}:$(calls)" "0:GET ${LK}SSH_PULL&fields=id,name
DELETE ${SI}/p1
GET ${LK}SSH_PUSH&fields=id,name
DELETE ${SI}/u1
GET ${LK}HTTP&fields=id,name"
has "04 DELETE: prints the code" "HTTP 204"
has "04 DELETE: and what it deleted" "Deleted the site 'SSH_PULL'."
has "04 DELETE: and what was not there (the HTTP site of 01)" "The account 'john' has no site 'HTTP'."
SWEEP_SEQ=$(seq s04b "$(sl 200 "${WORK}/pull_list.json")" 204 "$(sl 200 "${WORK}/push_list.json")" 204 "$(sl 200 "$(body http_list "${HTTP_LIST}")")" 204) run "${F}/04.sites_id_DELETE.sh"
expect "04 DELETE: the HTTP site that 01 creates is deleted too" "${RC}:$(calls | tail -n 1)" "0:DELETE ${SI}/h1"
expect "04 DELETE: names that only match the wildcard or the case (SSH_PULL2, ssh_pull) are never deleted" "$(calls | grep -c 'DELETE .*/p[89]$')" "0"
SWEEP_SEQ=$(seq s04c "$(sl 200 "${WORK}/pull_list.json")" "$(sl 400 "${WORK}/refused.json")" "$(sl 200 "${WORK}/push_list.json")" 204 "$(sl 200 "${WORK}/none.json")") run "${F}/04.sites_id_DELETE.sh"
expect "04 DELETE: a refused delete exits 1, the others are still tried" "${RC}:$(calls | grep -c '^DELETE')" "1:2"
has "04 DELETE: and shows the code" "HTTP 400"
SWEEP_SEQ=$(seq s04d "$(sl 200 "$(body pull_two '{"result":[{"id":"a","name":"SSH_PULL"},{"id":"b","name":"SSH_PULL"}]}')")" "$(sl 200 "${WORK}/none.json")") run "${F}/04.sites_id_DELETE.sh"
expect "04 DELETE: two sites with the exact name: none deleted, exit 1" "${RC}:$(calls | grep -c '^DELETE')" "1:0"
SWEEP_SEQ=$(seq s04e "$(sl 500 "${WORK}/refused.json")" "$(sl 200 "${WORK}/none.json")") run "${F}/04.sites_id_DELETE.sh"
expect "04 DELETE: a lookup the server refuses exits 1 (it is not 'no site')" "${RC}" "1"
reset
run "${F}/04.sites_id_DELETE.sh" john
bad_args "04 DELETE: an argument is refused, nothing sent"

# ==============================================================================
echo
echo "=== 07.Subscriptions/02.subscriptions_POST.sh ==="
F=07.Subscriptions
SU="${BASE}/subscriptions"
APP_EXISTS='{"message":"Error validating request","validationErrors":["An application with this name already exists."]}'
SWEEP_SEQ=$(seq s02 201 201) LOCATION=newsubid run "${F}/02.subscriptions_POST.sh"
expect "02 POST: the application, then the subscription; exit 0" "${RC}:$(calls)" "0:POST ${BASE}/applications
POST ${SU}"
expect "02 POST: the application body" "$(payload 1 | jq -c .)" '{"type":"AdvancedRouting","name":"AdvancedRoutingApplication","notes":"Created by 07.Subscriptions"}'
expect "02 POST: the subscription body pulls with SSH_PULL" "$(payload 2 | jq -c .)" \
  '{"type":"AdvancedRouting","account":"john","application":"AdvancedRoutingApplication","folder":"/inbox","transferConfigurations":[{"tag":"PARTNER-IN","outbound":false,"site":"SSH_PULL"}]}'
expect "02 POST: prints the code of each" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 201$')" "2"
has "02 POST: and the new id from Location" "New subscription ID: newsubid"
SWEEP_SEQ=$(seq s02b 201 201) LOCATION=newsubid SWEEP_CONTINUE=1 run "${F}/02.subscriptions_POST.sh"
hasnt "02 POST: a 100 Continue block in the headers file does not change the code (it used to print HTTP 100)" "HTTP 100"
has "02 POST: it says 201" "HTTP 201"
SWEEP_SEQ=$(seq s02c "$(sl 400 "$(body app_exists "${APP_EXISTS}")")" 201) LOCATION=newsubid run "${F}/02.subscriptions_POST.sh"
expect "02 POST: an application that exists is no failure: the subscription goes on it; exit 0" "${RC}:$(calls | grep -c '^POST')" "0:2"
has "02 POST: and it says so" "The application exists already"
SWEEP_SEQ=$(seq s02d "$(sl 403 "$(body app_forbidden '{"message":"Forbidden","validationErrors":null}')")" 201) run "${F}/02.subscriptions_POST.sh"
expect "02 POST: any other refusal of the application exits 1 and stops" "${RC}:$(calls | grep -c '^POST')" "1:1"
SWEEP_SEQ=$(seq s02e 201 "$(sl 404 "$(body no_site '{"message":"Error validating request","validationErrors":["Site SSH_PULL not found."]}')")") run "${F}/02.subscriptions_POST.sh"
expect "02 POST: a refused subscription exits 1" "${RC}" "1"
has "02 POST: with the server's message" "Site SSH_PULL not found."
reset
run "${F}/02.subscriptions_POST.sh" extra
bad_args "02 POST: an argument is refused, nothing sent"

echo
echo "=== 07.Subscriptions/03.subscriptions_POST_triggerfile.sh ==="
STATUS=201 LOCATION=trigid run "${F}/03.subscriptions_POST_triggerfile.sh"
expect "03 POST: one POST of the subscription; exit 0" "${RC}:$(calls)" "0:POST ${SU}"
expect "03 POST: the trigger condition keeps its two backslashes, the file name its EL" \
  "$(payload 1 | jq -c '[.folder, .postTransmissionActions.triggerOnConditionExpression, .createFilesList.createFilesListFilename]')" \
  "[\"/inbox-trigger\",\"\${stenv['target'].matches('.*\\\\\\\\.trigger')?1:0}\",\"file_\${date('yyyyddMMHHmmss')}.trigger\"]"
has "03 POST: prints the code" "HTTP 201"
has "03 POST: and the new id" "New subscription ID: trigid"
STATUS=201 LOCATION=trigid SWEEP_CONTINUE=1 run "${F}/03.subscriptions_POST_triggerfile.sh"
hasnt "03 POST: a 100 Continue block does not change the code" "HTTP 100"
STATUS=400 POST_BODY="${WORK}/app_exists.json" run "${F}/03.subscriptions_POST_triggerfile.sh"
expect "03 POST: a refusal exits 1, with the code and the message" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 400\|already exists')" "1:2"
reset
run "${F}/03.subscriptions_POST_triggerfile.sh" extra
bad_args "03 POST: an argument is refused, nothing sent"

echo
echo "=== 07.Subscriptions/04.subscriptions_id_DELETE.sh ==="
AR_APP="AdvancedRoutingApplication"
LK="${SU}?account=john&application=${AR_APP}&fields=id,application,folder"
SUB_LIST='{"result":[{"id":"s1","application":"AdvancedRoutingApplication","folder":"/inbox"},{"id":"s2","application":"AdvancedRoutingApplication","folder":"/inbox-trigger"},{"id":"s3","application":"AdvancedRoutingApplication","folder":"/inbox2"}]}'
SWEEP_SEQ=$(seq s0407 "$(sl 200 "$(body sub_list "${SUB_LIST}")")" 204 "$(sl 200 "${WORK}/sub_list.json")" 204 204) run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: looks each folder up by account and application, deletes the exact folder, then the application; exit 0" "${RC}:$(calls)" "0:GET ${LK}
DELETE ${SU}/s1
GET ${LK}
DELETE ${SU}/s2
DELETE ${BASE}/applications/${AR_APP}"
expect "04 DELETE: prints the code of each delete" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 204$')" "3"
has "04 DELETE: and what it deleted" "Deleted the subscription on '/inbox'."
SWEEP_SEQ=$(seq s0408 "$(sl 200 "${WORK}/sub_list.json")" "$(sl 400 "${WORK}/refused.json")" "$(sl 200 "${WORK}/sub_list.json")" 204 204) run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: a refused delete exits 1, the rest is still tried" "${RC}:$(calls | grep -c '^DELETE')" "1:3"
SWEEP_SEQ=$(seq s0409 "$(sl 200 "$(body sub_two '{"result":[{"id":"a","application":"AdvancedRoutingApplication","folder":"/inbox"},{"id":"b","application":"AdvancedRoutingApplication","folder":"/inbox"}]}')")" "$(sl 200 "${WORK}/none.json")" 204) run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: two subscriptions on one folder: none deleted, exit 1" "${RC}:$(calls | grep -c '^DELETE .*/subscriptions/')" "1:0"
SWEEP_SEQ=$(seq s0410 "$(sl 200 "${WORK}/none.json")" "$(sl 200 "${WORK}/none.json")" 404) run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: nothing found and no application (404): exit 0" "${RC}" "0"
has "04 DELETE: says so" "There is no application 'AdvancedRoutingApplication'."
SWEEP_SEQ=$(seq s0411 "$(sl 200 "${WORK}/none.json")" "$(sl 200 "${WORK}/none.json")" "$(sl 400 "$(body app_active '{"message":"Error validating request","validationErrors":["Application AdvancedRoutingApplication has active subscriptions"]}')")") run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: an application with subscriptions is refused: exit 1" "${RC}" "1"
has "04 DELETE: with the server's message" "has active subscriptions"
SWEEP_SEQ=$(seq s0412 500 500 204) run "${F}/04.subscriptions_id_DELETE.sh"
expect "04 DELETE: a lookup the server refuses exits 1" "${RC}" "1"
reset
run "${F}/04.subscriptions_id_DELETE.sh" extra
bad_args "04 DELETE: an argument is refused, nothing sent"

echo
echo "=== 07.Subscriptions/12.subscriptions_POST_types.sh ==="
SWEEP_SEQ=$(seq s12t 201) LOCATION=newid run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 types: an application and a subscription for each of four types, exit 0" "${RC}:$(ncalls)" "0:8"
expect "12 types: prints the code of every call" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 201$')" "8"
expect "12 types: and four new ids" "$(printf '%s\n' "${OUT}" | grep -c 'New subscription ID: newid')" "4"
SWEEP_SEQ=$(seq s12t2 201) LOCATION=newid SWEEP_CONTINUE=1 run "${F}/12.subscriptions_POST_types.sh" example_acct
hasnt "12 types: a 100 Continue block does not change the code (it printed HTTP 100)" "HTTP 100"
SWEEP_SEQ=$(seq s12t3 201 "$(sl 500 "${WORK}/refused.json")" 201 201 201 201 201 201) LOCATION=newid run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 types: a refused subscription exits 1, the other types are still tried" "${RC}:$(calls | grep -c "POST ${SU}\$")" "1:4"
SWEEP_SEQ=$(seq s12t4 "$(sl 403 "${WORK}/app_forbidden.json")" 201 201 201 201 201 201 201) LOCATION=newid run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 types: an application the server refuses (not 'exists') skips its subscription and exits 1" "${RC}:$(calls | grep -c "POST ${SU}\$")" "1:3"
SWEEP_SEQ=$(seq s12t5 "$(sl 400 "${WORK}/app_exists.json")" 201 "$(sl 400 "${WORK}/app_exists.json")" 201 "$(sl 400 "${WORK}/app_exists.json")" 201 "$(sl 400 "${WORK}/app_exists.json")" 201) LOCATION=newid run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 types: applications that exist already are no failure: exit 0, four subscriptions" "${RC}:$(calls | grep -c "POST ${SU}\$")" "0:4"
reset
run "${F}/12.subscriptions_POST_types.sh" a b
bad_args "12 types: two arguments, nothing sent"

echo
echo "=== 07.Subscriptions/13.subscriptions_id_DELETE_types.sh ==="
TYPE_LK="${SU}?account=example_acct&application=ExampleBasicApplication&fields=id,application,folder"
ONE='{"result":[{"id":"b1id","application":"ExampleBasicApplication","folder":"/example_Basic"},{"id":"zz","application":"ExampleBasicApplication","folder":"/example_basic"}]}'
SWEEP_SEQ=$(seq s13t "$(sl 200 "$(body type_one "${ONE}")")" 204 204 "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204) run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 types: the lookup is exact on the folder (a folder that differs by case is not the one), the delete purges, the application goes" "$(calls | head -3)" "GET ${TYPE_LK}
DELETE ${SU}/b1id?purge=true
DELETE ${BASE}/applications/ExampleBasicApplication"
expect "13 types: exit 0 when everything answered as it should" "${RC}" "0"
SWEEP_SEQ=$(seq s13t2 "$(sl 200 "${WORK}/type_one.json")" "$(sl 400 "${WORK}/refused.json")" 204 "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204) run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 types: a refused delete exits 1, the application is still deleted and the other types tried" "${RC}:$(calls | grep -c '^DELETE')" "1:5"
SWEEP_SEQ=$(seq s13t3 "$(sl 200 "${WORK}/none.json")" 404 "$(sl 200 "${WORK}/none.json")" 404 "$(sl 200 "${WORK}/none.json")" 404 "$(sl 200 "${WORK}/none.json")" 404) run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 types: nothing found and no application (404) is no failure" "${RC}" "0"
SWEEP_SEQ=$(seq s13t4 "$(sl 200 "${WORK}/none.json")" "$(sl 400 "$(body app_active2 '{"message":"x","validationErrors":["Application has active subscriptions"]}')")" "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204 "$(sl 200 "${WORK}/none.json")" 204) run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 types: an application the server refuses to delete exits 1" "${RC}" "1"
has "13 types: with the message" "has active subscriptions"
SWEEP_SEQ=$(seq s13t5 500 204 500 204 500 204 500 204) run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 types: a lookup the server refuses exits 1 (it is not 'none found')" "${RC}" "1"
reset
run "${F}/13.subscriptions_id_DELETE_types.sh" a b
bad_args "13 types: two arguments, nothing sent"

# ==============================================================================
echo
echo "=== 08.RouteTemplates/02.routes_POST.sh and 03.routes_DELETE_all.sh ==="
F=08.RouteTemplates
R="${BASE}/routes"
# the full list: 163 names
EXISTING='{"result":[{"name":"RouteFromEngineer"},{"name":"MyOwnTemplate"}]}'
SWEEP_SEQ=$(seq s0802 "$(sl 200 "$(body templates "${EXISTING}")")" 201) run "${F}/02.routes_POST.sh"
expect "02 templates: one read of the existing templates, then 162 POSTs (RouteFromEngineer exists, so it is skipped); exit 0" "${RC}:$(calls | head -1):$(calls | grep -c "^POST ${R}\$")" "0:GET ${R}?type=TEMPLATE&fields=name&limit=200&offset=0:162"
expect "02 templates: the body of the first one posted is built by jq" "$(payload 1 | jq -c .)" '{"name":"RouteFromGovernment","description":"Random text for RouteFromGovernment","type":"TEMPLATE","conditionType":"MATCH_ALL"}'
has "02 templates: shows a count" "[1/163] RouteFromEngineer exists already: skipped"
has "02 templates: and a count with the code" "[163/163] RouteFromGuide HTTP 201"
has "02 templates: and a summary" "Done: 162 route templates created, 1 already there."
# a trimmed copy for the refusals: four names
mkdir -p "${WORK}/admin/${F}"
python3 - "${ADMIN_TREE}/${F}/02.routes_POST.sh" "${WORK}/admin/${F}/trim_02.sh" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
trimmed = text[:text.index("declare -a TEMPLATE_NAMES=(")] + 'declare -a TEMPLATE_NAMES=(\n        "RouteFromOne" "RouteFromTwo" "RouteFromThree" "RouteFromFour"\n)\n' + text[text.index("\n)\n", text.index("declare -a TEMPLATE_NAMES=(")) + 3:]
open(sys.argv[2], "w").write(trimmed)
PY
run_trim() {
    rm -f "${SWEEP_SEQ:-/nonexistent}.n"
    OUT=$(cd "${WORK}/admin/${F}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_PRINT_CODE=1 STUB_CURL_STATUS=200 SWEEP_SEQ="${SWEEP_SEQ:-}" \
          bash "./trim_02.sh" "$@" 2>&1)
    RC=$?
}
SWEEP_SEQ=$(seq s0802b "$(sl 200 "$(body none_t "${NONE}")")" 201 201 "$(sl 403 "$(body forbidden '{"message":"Forbidden","validationErrors":["No permission"]}')")" 201) run_trim
expect "02 templates: the first refusal stops the script: exit 1, and the fourth name is never sent" "${RC}:$(calls | grep -c "^POST")" "1:3"
has "02 templates: it shows the code and the server's message" "[3/4] RouteFromThree HTTP 403"
has "02 templates: and how far it got" "Stopped at the first refusal: 2 created, 0 skipped, 1 not tried."
SWEEP_SEQ=$(seq s0802c "$(sl 200 "$(body templates_all '{"result":[{"name":"RouteFromOne"},{"name":"RouteFromTwo"},{"name":"RouteFromThree"},{"name":"RouteFromFour"}]}')")") run_trim
expect "02 templates: a second run, with every template there: nothing posted, exit 0" "${RC}:$(calls | grep -c '^POST')" "0:0"
SWEEP_SEQ=$(seq s0802d "$(sl 500 "${WORK}/refused.json")") run_trim
expect "02 templates: a read of the templates that fails: exit 1, nothing posted" "${RC}:$(calls | grep -c '^POST')" "1:0"
SWEEP_SEQ= run_trim extra
expect "02 templates: an argument is refused: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
reset

# 03: delete exactly the 163 names
ALL_TEMPLATES='{"result":[{"id":"e1","name":"RouteFromEngineer","type":"TEMPLATE"},{"id":"g1","name":"RouteFromGovernment","type":"TEMPLATE"},{"id":"o1","name":"RouteFromSomethingOfMine","type":"TEMPLATE"},{"id":"o2","name":"routefromclient","type":"TEMPLATE"},{"id":"o3","name":"MyOwnTemplate","type":"TEMPLATE"}]}'
SWEEP_SEQ=$(seq s0803 "$(sl 200 "$(body all_templates "${ALL_TEMPLATES}")")" 204) run "${F}/03.routes_DELETE_all.sh"
expect "03 delete: one read of the route templates, then a DELETE of each name of the list that exists, by id; exit 0" "${RC}:$(calls)" "0:GET ${R}?type=TEMPLATE&fields=id,name&limit=200&offset=0
DELETE ${R}/e1
DELETE ${R}/g1"
expect "03 delete: a template of its own, even one called RouteFrom..., and one that differs by case are never deleted" "$(calls | grep -c 'DELETE .*/o[123]$')" "0"
has "03 delete: shows a count and the code" "[1/163] RouteFromEngineer (e1) HTTP 204"
has "03 delete: and a summary" "Done: 2 route templates deleted, 161 were not there."
SWEEP_SEQ=$(seq s0803b "$(sl 200 "${WORK}/all_templates.json")" "$(sl 400 "$(body in_use '{"message":"Error validating request","validationErrors":["Route is in use."]}')")" 204) run "${F}/03.routes_DELETE_all.sh"
expect "03 delete: the first refusal stops the script: exit 1, the second template is never deleted" "${RC}:$(calls | grep -c '^DELETE')" "1:1"
has "03 delete: it shows the server's message" "Route is in use."
has "03 delete: and how far it got" "Stopped at the first refusal: 0 deleted, 0 skipped, 162 not tried."
SWEEP_SEQ=$(seq s0803c "$(sl 500 "${WORK}/refused.json")") run "${F}/03.routes_DELETE_all.sh"
expect "03 delete: a read that fails: exit 1, nothing deleted" "${RC}:$(calls | grep -c '^DELETE')" "1:0"
SWEEP_SEQ=$(seq s0803d "$(sl 200 "$(body dup_templates '{"result":[{"id":"e1","name":"RouteFromEngineer"},{"id":"e2","name":"RouteFromEngineer"}]}')")" 204) run "${F}/03.routes_DELETE_all.sh"
expect "03 delete: two templates with one name of the list: none deleted, exit 1" "${RC}:$(calls | grep -c '^DELETE')" "1:0"
SWEEP_SEQ=$(seq s0803e "$(sl 200 "${WORK}/none.json")") run "${F}/03.routes_DELETE_all.sh"
expect "03 delete: none of the templates there: nothing deleted, exit 0" "${RC}:$(calls | grep -c '^DELETE')" "0:0"
reset
run "${F}/03.routes_DELETE_all.sh" extra
bad_args "03 delete: an argument is refused, nothing sent"
# the two scripts hold the same 163 names
NAMES_02=$(grep -o '"RouteFrom[A-Za-z]*"' "${ADMIN_TREE}/${F}/02.routes_POST.sh" | sort | tr '\n' ' ')
NAMES_03=$(grep -o '"RouteFrom[A-Za-z]*"' "${ADMIN_TREE}/${F}/03.routes_DELETE_all.sh" | sort | tr '\n' ' ')
expect "03 delete: the list of names is the one 02 creates" "${NAMES_03}" "${NAMES_02}"
expect "03 delete: and it has 163 of them" "$(printf '%s' "${NAMES_03}" | wc -w | tr -d ' ')" "163"
BAT_NAMES_02=$(grep -vE '^REM' "${BAT_TREE}/${F}/02.routes_POST.bat" | grep -o 'RouteFrom[A-Za-z]*' | sort -u | tr '\n' ' ')
BAT_NAMES_03=$(grep -vE '^REM' "${BAT_TREE}/${F}/03.routes_DELETE_all.bat" | grep -o 'RouteFrom[A-Za-z]*' | sort -u | tr '\n' ' ')
BASH_NAMES=$(printf '%s' "${NAMES_02}" | tr -d '"' | tr ' ' '\n' | sort -u | tr '\n' ' ')
expect "03 delete (bat): the same 163 names as the bash one" "${BAT_NAMES_03}" "${BASH_NAMES}"
expect "02 templates (bat): the same 163 names too" "${BAT_NAMES_02}" "${BASH_NAMES}"

# ==============================================================================
echo
echo "=== 09.CompositeRoutes/03, 04 and 07 ==="
F=09.CompositeRoutes
for pair in "03.routes_POST_simple_compress.sh:SimpleRoute_Compress:Compress" "04.routes_POST_simple_decompress.sh:SimpleRoute_Decompress:Decompress"; do
    script="${pair%%:*}"; rest="${pair#*:}"; name="${rest%%:*}"; first="${rest#*:}"; n="${script%%.*}"
    STATUS=201 LOCATION=newrouteid run "${F}/${script}"
    expect "${n} simple route: one POST of the route; exit 0" "${RC}:$(calls)" "0:POST ${R}"
    expect "${n} simple route: ${name}, ${first} then SendToPartner to SSH_PUSH" "$(payload 1 | jq -c '[.name, .type, [.steps[].type], .steps[1].transferSiteExpression]')" "[\"${name}\",\"SIMPLE\",[\"${first}\",\"SendToPartner\"],\"SSH_PUSH#!#CVD#!#\"]"
    has "${n} simple route: prints the code" "HTTP 201"
    has "${n} simple route: and the new id" "New route ID: newrouteid"
    STATUS=201 LOCATION=newrouteid SWEEP_CONTINUE=1 run "${F}/${script}"
    hasnt "${n} simple route: a 100 Continue block does not change the code" "HTTP 100"
    STATUS=400 POST_BODY=$(body route_bad '{"message":"Error validating request","validationErrors":["steps[0].compressionType must not be null"]}') run "${F}/${script}"
    expect "${n} simple route: a refusal exits 1" "${RC}" "1"
    has "${n} simple route: with the code" "HTTP 400"
    has "${n} simple route: and the server's message" "must not be null"
    reset
    run "${F}/${script}" extra
    bad_args "${n} simple route: an argument is refused, nothing sent"
done

# 07: composite first, then simple; the composite one of the account only; exact names; ambiguity refused
RT='{"result":[{"id":"%s","name":"%s","type":"%s","account":"%s"},{"id":"x9","name":"%s_other","type":"%s","account":"%s"}]}'
mk() { printf "${RT}\n" "$1" "$2" "$3" "$4" "$2" "$3" "$4"; }
printf 'name=CompositeRoute_Subscription\t%s\nname=CompositeRoute_WithExtension\t%s\nname=CompositeRoute_WithoutExtension\t%s\nname=SimpleRoute_Compress\t%s\nname=SimpleRoute_Decompress\t%s\nname=SimpleRouteName\t%s\n' \
  "$(body r_c1 "$(mk c1 CompositeRoute_Subscription COMPOSITE john)")" "$(body r_c2 "$(mk c2 CompositeRoute_WithExtension COMPOSITE john)")" \
  "$(body r_c3 "$(mk c3 CompositeRoute_WithoutExtension COMPOSITE john)")" "$(body r_s1 "$(mk s1 SimpleRoute_Compress SIMPLE '')")" \
  "$(body r_s2 "$(mk s2 SimpleRoute_Decompress SIMPLE '')")" "$(body r_s3 "$(mk s3 SimpleRouteName SIMPLE '')")" > "${WORK}/rules_07.tsv"
RULES="${WORK}/rules_07.tsv" STATUS=204 STATUS_GET=200 run "${F}/07.routes_id_DELETE.sh"
expect "07 DELETE: looks each of the six routes up by type and name (encoded), deletes it by the id found; the composite routes first; exit 0" "${RC}:$(calls)" "0:GET ${R}?type=COMPOSITE&name=CompositeRoute_Subscription
DELETE ${R}/c1
GET ${R}?type=COMPOSITE&name=CompositeRoute_WithExtension
DELETE ${R}/c2
GET ${R}?type=COMPOSITE&name=CompositeRoute_WithoutExtension
DELETE ${R}/c3
GET ${R}?type=SIMPLE&name=SimpleRoute_Compress
DELETE ${R}/s1
GET ${R}?type=SIMPLE&name=SimpleRoute_Decompress
DELETE ${R}/s2
GET ${R}?type=SIMPLE&name=SimpleRouteName
DELETE ${R}/s3"
expect "07 DELETE: prints the code of each delete" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 204$')" "6"
has "07 DELETE: and what it deleted" "Deleted the COMPOSITE route 'CompositeRoute_Subscription'."
expect "07 DELETE: a route whose name only matches the wildcard (..._other) is never deleted" "$(calls | grep -c 'DELETE .*/x9$')" "0"
# another account's composite route
OTHER_ACCOUNT=$(body r_c1_other '{"result":[{"id":"c9","name":"CompositeRoute_Subscription","type":"COMPOSITE","account":"someone_else"}]}')
printf 'name=CompositeRoute_Subscription\t%s\n' "${OTHER_ACCOUNT}" > "${WORK}/rules_07b.tsv"
RULES="${WORK}/rules_07b.tsv" STATUS=204 STATUS_GET=200 GET_BODY="${WORK}/none.json" run "${F}/07.routes_id_DELETE.sh"
expect "07 DELETE: another account's composite route of that name is left alone" "$(calls | grep -c 'DELETE .*/c9$')" "0"
has "07 DELETE: and it says there is none" "There is no COMPOSITE route 'CompositeRoute_Subscription'."
# two simple routes with one name
TWO_SIMPLE=$(body r_two '{"result":[{"id":"t1","name":"SimpleRoute_Compress","type":"SIMPLE"},{"id":"t2","name":"SimpleRoute_Compress","type":"SIMPLE"}]}')
printf 'name=SimpleRoute_Compress\t%s\n' "${TWO_SIMPLE}" > "${WORK}/rules_07c.tsv"
RULES="${WORK}/rules_07c.tsv" STATUS=204 STATUS_GET=200 GET_BODY="${WORK}/none.json" run "${F}/07.routes_id_DELETE.sh"
expect "07 DELETE: two simple routes with one name: neither is deleted, exit 1" "${RC}:$(calls | grep -c 'DELETE .*/t[12]$')" "1:0"
has "07 DELETE: says so" "There are 2 SIMPLE routes named 'SimpleRoute_Compress'; none deleted."
# a delete the server refuses
RULES="${WORK}/rules_07.tsv" STATUS=400 STATUS_GET=200 run "${F}/07.routes_id_DELETE.sh"
expect "07 DELETE: a refused delete exits 1, the others are still tried" "${RC}:$(calls | grep -c '^DELETE')" "1:6"
has "07 DELETE: with the code" "HTTP 400"
STATUS=500 STATUS_GET=500 run "${F}/07.routes_id_DELETE.sh"
expect "07 DELETE: a lookup the server refuses exits 1 and deletes nothing" "${RC}:$(calls | grep -c '^DELETE')" "1:0"
reset
run "${F}/07.routes_id_DELETE.sh" extra
bad_args "07 DELETE: an argument is refused, nothing sent"

# ==============================================================================
echo
echo "=== the bat twins: the same guards and the same status handling ==="
BAT_FILES=(
    "03.Connect/07.servers_POST.bat" "03.Connect/10.servers_name_PUT.bat" "03.Connect/11.servers_name_PATCH.bat" "03.Connect/12.servers_name_DELETE.bat"
    "03.Connect/13.servers_operations_POST.bat" "06.TransferSites/01.sites_POST.bat" "06.TransferSites/02.sites_POST_ssh.bat"
    "06.TransferSites/04.sites_id_DELETE.bat" "07.Subscriptions/02.subscriptions_POST.bat" "07.Subscriptions/03.subscriptions_POST_triggerfile.bat"
    "07.Subscriptions/04.subscriptions_id_DELETE.bat" "07.Subscriptions/12.subscriptions_POST_types.bat" "07.Subscriptions/13.subscriptions_id_DELETE_types.bat"
    "08.RouteTemplates/02.routes_POST.bat" "08.RouteTemplates/03.routes_DELETE_all.bat" "09.CompositeRoutes/03.routes_POST_simple_compress.bat"
    "09.CompositeRoutes/04.routes_POST_simple_decompress.bat" "09.CompositeRoutes/07.routes_id_DELETE.bat" )
for rel in "${BAT_FILES[@]}"; do
    bat="${BAT_TREE}/${rel}"
    sh="${ADMIN_TREE}/${rel%.bat}.sh"
    [ -f "${bat}" ] || { fail "${rel}: the bat twin is missing"; continue; }
    expect "${rel}: prints HTTP <code> from curl -w, never from a headers file" "$(grep -c 'HTTP %HTTP_CODE%' "${bat}" | awk '{print ($1 > 0)}')" "1"
    expect "${rel}: no status taken from the head of a headers file" "$(grep -vE '^REM' "${bat}" | grep -cE 'HEADERS_FILE.*Select-Object -First 1|findstr /B /I "HTTP/"')" "0"
    expect "${rel}: curl -w always uses %%{http_code}" "$(grep -cE '(^|[^%])%\{http_code\}' "${bat}")" "0"
    expect "${rel}: exits 1 when the server refuses a call, 0 on success" "$(grep -cE 'EXIT /B (1|%RC%|%FAILED%)|IF NOT "%FAILED%"=="0" EXIT /B 1' "${bat}" | awk '{print ($1 > 0)}')" "1"
    expect "${rel}: the same Risk line as the bash twin" "$(grep -m1 '^REM Risk:' "${bat}" | tr -d '\r' | sed 's/^REM //')" "$(grep -m1 '^# Risk:' "${sh}" | sed 's/^# //')"
    expect "${rel}: no JSON built by string substitution (no -d with a pasted value)" "$(grep -vE '^REM' "${bat}" | grep -cE '\-d "\{')" "0"
done
for rel in 03.Connect/07.servers_POST 03.Connect/10.servers_name_PUT 03.Connect/11.servers_name_PATCH 03.Connect/13.servers_operations_POST \
           06.TransferSites/02.sites_POST_ssh 08.RouteTemplates/02.routes_POST; do
    expect "${rel}.bat: bad arguments exit 2 before anything is sent" "$(grep -c 'EXIT /B 2' "${BAT_TREE}/${rel}.bat" | awk '{print ($1 > 0)}')" "1"
done
expect "13 (bat): the confirmation word of a stop is in the usage, like the bash twin's" "$(grep -c 'stop-the-' "${BAT_TREE}/03.Connect/13.servers_operations_POST.bat" | awk '{print ($1 > 1)}')" "1"
expect "02 ssh (bat): no placeholder password default" "$(grep -vE '^REM' "${BAT_TREE}/06.TransferSites/02.sites_POST_ssh.bat" | grep -c 'SET PARTNER_PASSWORD=change_me')" "0"
expect "04 sites (bat): deletes the HTTP site too" "$(grep -c 'FOR %%N IN (SSH_PULL SSH_PUSH HTTP)' "${BAT_TREE}/06.TransferSites/04.sites_id_DELETE.bat")" "1"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_sweep_a: PASS"
else
    echo "test_bash_admin_sweep_a: FAIL"
fi
exit "${FAILED}"
