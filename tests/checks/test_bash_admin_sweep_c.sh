#!/bin/bash
# ==============================================================================
# Sweep C: the older Admin READ examples that never looked at the HTTP status.
# Before, a 401 or a 500 on a list printed nothing, or an HTML page, and the
# script exited 0, so a failed read looked like an empty answer. Now each call is
# read with curl -w, and a status other than 200 prints "HTTP <code>" and the
# server's answer and exits 1. This file runs them against a stub curl:
#
#   - success: the stdout and the calls are exactly what the script printed and
#     sent before (recorded from the old scripts with synthetic answers);
#   - a 401 (the plain text the lab sends) and a 500 (an HTML page): exit 1, the
#     status and the answer printed, and no more calls than the first, no jq
#     error from reading text as JSON;
#   - an argument that is wrong, or one too many, is exit 2 with nothing sent;
#   - the particular ones: the login POST of 01.Authentication, the session
#     scripts, the HEAD of a server, the exit code of the greps, the password of
#     18.AccountSetup, the routes that are created, and the daily count.
#
# 22.DeniedUsers to 28.ServerLogs, 36.UserClasses, 11.Certificates/01 and
# 16.TransferLogs/02 are here too: they had the same fault. The bat twins cannot
# run here: their text is checked at the end (the status read with %%{http_code}
# and compared, exit codes, usage, nothing printed straight from curl).
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
ADMIN_TREE="${REPO}/Admin/API 2.0/bash"
BAT_TREE="${REPO}/Admin/API 2.0/bat"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_sweep_c"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin" "${WORK}/tmp"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

# curl: the stub, with a status of its own for each method (see stub_curl_by_method)
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
BASE="https://st.example.com:8444/api/v2.0"

# rules TEXT FILE [TEXT FILE...]: a file of answers by URL, for a script that reads several things (the stub gives the first FILE
# whose TEXT is in the URL, and GET_BODY to a URL that none matches)
RULE_N=0
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# body NAME TEXT: a canned answer, in a file, as the server sends it (no newline at the end)
body() { printf '%s' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
SUPER_JSON='{"resultSet": {"returnCount": 1, "totalCount": 7}, "result": [{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}]}'
ARRAY_JSON='[{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}]'
PLAIN_JSON='{"banner": "", "sshStatus": "Running", "os": "Linux", "version": "5.5-1", "serverType": "ST", "loginName": "admin", "lastPasswordChangeTime": "2026-01-01", "maxConnections": 50}'
B_SUPER=$(body super "${SUPER_JSON}")
B_ARRAY=$(body array "${ARRAY_JSON}")
B_PLAIN=$(body plain "${PLAIN_JSON}")
B_ITEM=$(body item '{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}')
B_FP=$(body fp '{"fingerprint": "AB:CD:EF"}')
B_401=$(body refused_401 'Authentication required.')
B_500=$(body refused_500 '<!doctype html><html><head><title>HTTP Status 500 - Internal Server Error</title></head><body>Boom</body></html>')

# run FOLDER/SCRIPT ARGS...: GET_BODY and POST_BODY are what the GETs and POSTs answer; LOCATION, the id in the Location of
# a POST (LOC_PREFIX: one per POST, prefix1, prefix2, ...); CSRF, the csrfToken of a login; ST_GET, ST_POST, ST_PUT, ST_DELETE,
# ST_HEAD the status of each method (200, 201, 204, 204, 200 when not set); ST_GET_SEQ, ST_POST_SEQ a status for each call in
# turn; ERR_BODY what a PUT, PATCH, DELETE or HEAD answers with. The stdout is OUT, what the stub reports is ERRS.
run() {
    local rel="$1"; shift
    mkdir -p "${WORK}/admin/$(dirname "${rel}")"
    cp "${ADMIN_TREE}/${rel}" "${WORK}/admin/${rel}"
    rm -f "${WORK}/counter."*
    ( cd "${WORK}/admin/$(dirname "${rel}")" && PATH="${WORK}/bin:${PATH}" TMPDIR="${WORK}/tmp" STUB_COUNTER="${WORK}/counter" STUB_CURL_PRINT_CODE=1 \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_LOCATION_ID="${LOCATION:-}" STUB_LOCATION_PREFIX="${LOC_PREFIX:-}" \
          STUB_CURL_CSRF="${CSRF:-}" STUB_BODY_OTHER="${ERR_BODY:-}" \
          STUB_STATUS_GET="${ST_GET:-200}" STUB_STATUS_POST="${ST_POST:-201}" STUB_STATUS_PUT="${ST_PUT:-204}" \
          STUB_STATUS_DELETE="${ST_DELETE:-204}" STUB_STATUS_HEAD="${ST_HEAD:-200}" \
          STUB_STATUS_GET_SEQ="${ST_GET_SEQ:-}" STUB_STATUS_POST_SEQ="${ST_POST_SEQ:-}" \
          bash "./$(basename "${rel}")" "$@" ) > "${WORK}/stdout.txt" 2> "${WORK}/stderr.txt"
    RC=$?
    OUT=$(cat "${WORK}/stdout.txt")
    ERRS=$(cat "${WORK}/stderr.txt")
}
calls() { printf '%s\n' "${ERRS}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | grep -c .; }
payload() { printf '%s\n' "${ERRS}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
# lines the stub echoed that carry TEXT (a header, a cookie)
echoed() { printf '%s\n' "${ERRS}" | grep -cF -- "$1"; }
# a number or a date that is today's, so that a test can compare the rest
norm() { sed -E 's/[0-9]{13}/TS/g; s/[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9:]{8} (GMT|[+-][0-9]{4})/DATE/g'; }
# jq or the shell complaining about text that is not JSON
noise() { printf '%s\n' "${ERRS}" | grep -cE 'jq: error|parse error|command not found|syntax error'; }

# expect_calls, expect_out: the calls and the stdout the script made before this change, as stdin; @@BASE@@ is the API's
# address and @@BODY@@ the answer the stub gives
expect_calls() { EXP_CALLS=$(cat); EXP_CALLS="${EXP_CALLS//@@BASE@@/${BASE}}"; }
expect_out() { EXP_OUT=$(cat); }

# read_check LABEL FOLDER/SCRIPT ARGS...: GET_BODY is the answer of the good run; METHOD=POST for a script that logs in
read_check() {
    local label="$1" rel="$2" m="${METHOD:-GET}" good="${GET_BODY}" text n st want
    shift 2
    text=$(cat "${good}")
    if [ "${m}" = "POST" ]; then ST_POST=200 POST_BODY="${good}" run "${rel}" "$@"; else run "${rel}" "$@"; fi
    want="${EXP_OUT//@@BODY@@/${text}}"
    if [ -n "${NORM}" ]; then
        expect "${label}: the calls are the ones it always made" "$(calls | norm)" "$(printf '%s' "${EXP_CALLS}" | norm)"
        expect "${label}: the output is what it always was" "$(printf '%s' "${OUT}" | norm)" "$(printf '%s' "${want}" | norm)"
    else
        expect "${label}: the calls are the ones it always made" "$(calls)" "${EXP_CALLS}"
        expect "${label}: the output is what it always was" "${OUT}" "${want}"
    fi
    expect "${label}: exit 0" "${RC}" "0"
    n=$(calls | grep -c .)
    for st in 401 500; do
        if [ "${st}" = "401" ]; then bodyfile="${B_401}"; else bodyfile="${B_500}"; fi
        if [ "${m}" = "POST" ]; then ST_POST="${st}" POST_BODY="${bodyfile}" RULES= run "${rel}" "$@"; else ST_GET="${st}" GET_BODY="${bodyfile}" RULES= run "${rel}" "$@"; fi
        expect "${label}: a ${st} is exit 1" "${RC}" "1"
        has "${label}: a ${st} prints its status" "HTTP ${st}"
        if [ "${st}" = "401" ]; then has "${label}: and the server's answer" "Authentication required."; else has "${label}: and the server's page" "Internal Server Error"; fi
        expect "${label}: a ${st} stops at the first call" "$(ncalls)" "1"
        expect "${label}: and no jq or shell error from reading it as JSON" "$(noise)" "0"
    done
}
# bad_args FOLDER/SCRIPT ARGS...: exit 2, nothing sent
bad_args() { local rel="$1"; shift; run "${rel}" "$@"; expect "$(basename "${rel}") $*: exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"; }


# ==============================================================================
# What they printed and sent before, and what a refusal does now (recorded from the
# old scripts with synthetic answers)
# ==============================================================================
NORM=

echo
echo "=== 02.Introduction ==="

expect_calls <<'EOF'
GET @@BASE@@/version
EOF
expect_out <<'EOF'
@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '02.Introduction/01' '02.Introduction/01.version_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/version
EOF
expect_out <<'EOF'
Loading variables into our context...
grep for the version...
@@BODY@@
grep for version.*5.5...
@@BODY@@
grep for serverType...
@@BODY@@
grep for os...
@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '02.Introduction/02' '02.Introduction/02.version_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/myself
GET @@BASE@@/myself
EOF
expect_out <<'EOF'
Loading variables into our context...


Querying the API to get information about the current user...
@@BODY@@

Querying the API again and filtering the response to find the last password change time...
@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '02.Introduction/03' '02.Introduction/03.myself_GET.sh'

expect_calls <<'EOF'
POST @@BASE@@/myself
EOF
expect_out <<'EOF'
@@BODY@@
EOF
METHOD=POST GET_BODY="${B_PLAIN}" read_check '02.Introduction/05' '02.Introduction/05.myself_POST.sh'

echo
echo "=== 03.Connect ==="

expect_calls <<'EOF'
GET @@BASE@@/daemons
GET @@BASE@@/daemons
GET @@BASE@@/daemons?fields=sshStatus
EOF
expect_out <<'EOF'
Loading variables into our context...
@@BODY@@@@BODY@@
@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '03.Connect/01' '03.Connect/01.daemons_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/daemons/ssh
GET @@BASE@@/daemons/ssh
EOF
expect_out <<'EOF'
Loading variables into our context...
@@BODY@@There is no banner defined.
Setting the banner...
There is a banner defined: 'This is a SecureTransport REST API test banner.'.
EOF
GET_BODY="${B_PLAIN}" read_check '03.Connect/02' '03.Connect/02.daemons_name_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/servers
GET @@BASE@@/servers?fields=id,serverName,isActive
GET @@BASE@@/servers?protocol=as2&fields=id,serverName,isActive
GET @@BASE@@/servers?limit=1&offset=0&serverName=Ssh%20Default&isActive=true&isFipsEnabled=false
GET @@BASE@@/servers?fields=isScpEnabled&protocol=ssh
EOF
expect_out <<'EOF'
Loading variables into our context...
@@BODY@@@@BODY@@@@BODY@@@@BODY@@@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '03.Connect/06' '03.Connect/06.servers_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/servers/SSH_TEST_SERVER_1
GET @@BASE@@/servers/SSH_TEST_SERVER_1?fields=isActive,port&protocol=ssh
EOF
expect_out <<'EOF'
Loading variables into our context...

Getting SSH_TEST_SERVER_1...
@@BODY@@
Getting SSH_TEST_SERVER_1 with applied fields...
@@BODY@@
EOF
GET_BODY="${B_PLAIN}" read_check '03.Connect/09' '03.Connect/09.servers_name_GET.sh'

echo
echo "=== 04.Applications ==="

expect_calls <<'EOF'
GET @@BASE@@/applications
GET @@BASE@@/applications?type=AccountFilePurge
GET @@BASE@@/applications?fields=type
EOF
expect_out <<'EOF'
Get all applications...
@@BODY@@From all applications get one based on the type 'AccountFilePurge'...
@@BODY@@Get only the type of the available applications...
@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '04.Applications/01' '04.Applications/01.applications_GET.sh'

echo
echo "=== 05.Accounts ==="

expect_calls <<'EOF'
GET @@BASE@@/accounts
EOF
expect_out <<'EOF'
Loading variables into our context...@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '05.Accounts/01' '05.Accounts/01.accounts_GET.sh'

echo
echo "=== 06.TransferSites ==="

expect_calls <<'EOF'
GET @@BASE@@/sites?account=john
GET @@BASE@@/sites?account=john&protocol=ssh
EOF
expect_out <<'EOF'
Get all the sites of the account 'john'...
@@BODY@@

Get only its SSH sites, one line each: id, name, host:port, folder...
obj-1  example  st.example.com:8022  /in
EOF
GET_BODY="${B_SUPER}" read_check '06.TransferSites/03' '06.TransferSites/03.sites_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/sites?account=john&name=example&fields=id,name
GET @@BASE@@/sites/obj-1
GET @@BASE@@/sites/obj-1?fields=name,host,port
EOF
expect_out <<'EOF'
The site example of john, id obj-1:
  type:             LOCAL
  protocol:         ssh
  partner:          st.example.com:8022
  user:             admin
  download folder:  /in
  upload folder:    /out
  max connections:  null
  access level:     null
  password:         -

Only some of its fields, with fields=name,host,port:
{"id":"obj-1","name":"example","loginName":"example_admin","roleName":"Example Role","host":"st.example.com","port":8022,"downloadFolder":"/in","uploadFolder":"/out","folder":"/inbox","application":"AdvancedRoutingApplication","account":"john","accountName":"john","routeTemplate":"tpl-1","subscriptions":["sub-1"],"parent":"root","locked":false,"menus":["Change Password","Audit Log"],"values":["v1"],"defaultValues":["d1"],"profileId":"p1","propagationStatus":"ok","protocol":"ssh","active":true,"baseUrl":"https://vault.example.com","uri":"/v1","cacheTimeout":600,"type":"LOCAL","parentGroup":"g1","businessUnitHierarchy":"/Finance","baseFolder":"/home/fin","description":"a description","isDefault":true,"edges":[{}],"blockedUntil":null,"blockedBy":"admin","note":"a note","status":"active","fullTarget":"/f","retryCount":0,"default":true,"sendMapping":"m1","receiveMapping":"m2","fileLabelOption":"label","transferMode":"mode","serverEnabled":true,"basicSettings":{"name":"icap1","type":"BOTH","url":"icap://x"},"ldapServers":[{"host":"ldap.example.com","port":389}],"ldapSearches":{"baseDn":"dc=example"},"rules":[{}],"businessUnits":["Finance"],"dateModified":"2026-10-01","operationType":"CREATE","objectType":"Account","objectName":"john","userName":"admin","remoteAddress":"10.0.0.1","time":"t1","level":"INFO","component":"TM","message":"hello","order":1,"className":"VirtClass","userType":"virtual","group":"*","address":"*","enabled":true,"expression":"","subject":"CN=x","expirationTime":1,"usage":"local","connectionType":"local","database":"all","user":"all","authMethod":"md5","serverName":"SSH_TEST","isActive":true,"sshStatus":"Running","banner":"","os":"Linux","version":"5.5-1","serverType":"ST","lastPasswordChangeTime":"x"}
EOF
RULES=$(rules '/sites/obj-1' "${B_ITEM}") GET_BODY="${B_SUPER}" read_check '06.TransferSites/06' '06.TransferSites/06.sites_id_GET.sh' 'john' 'example'

echo
echo "=== 07.Subscriptions ==="

expect_calls <<'EOF'
GET @@BASE@@/subscriptions?account=john
GET @@BASE@@/subscriptions?account=john&type=AdvancedRouting
EOF
expect_out <<'EOF'
Get all the subscriptions of the account 'john'...
@@BODY@@

Get only its Advanced Routing subscriptions, one line each: id, folder, application...
obj-1  /inbox  AdvancedRoutingApplication
EOF
GET_BODY="${B_SUPER}" read_check '07.Subscriptions/01' '07.Subscriptions/01.subscriptions_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/subscriptions?account=john&application=AdvancedRoutingApplication&fields=id,application,folder
GET @@BASE@@/subscriptions/obj-1
GET @@BASE@@/subscriptions/obj-1?fields=id,folder,fileRetentionPeriod
EOF
expect_out <<'EOF'
The subscription of john on AdvancedRoutingApplication, folder /inbox, id obj-1:
  type:              LOCAL
  retention (days):  -
  parallel pulls:    -
  pull sites:        -
  flow attributes:   0

Only some of its fields, with fields=id,folder,fileRetentionPeriod:
{"id":"obj-1","name":"example","loginName":"example_admin","roleName":"Example Role","host":"st.example.com","port":8022,"downloadFolder":"/in","uploadFolder":"/out","folder":"/inbox","application":"AdvancedRoutingApplication","account":"john","accountName":"john","routeTemplate":"tpl-1","subscriptions":["sub-1"],"parent":"root","locked":false,"menus":["Change Password","Audit Log"],"values":["v1"],"defaultValues":["d1"],"profileId":"p1","propagationStatus":"ok","protocol":"ssh","active":true,"baseUrl":"https://vault.example.com","uri":"/v1","cacheTimeout":600,"type":"LOCAL","parentGroup":"g1","businessUnitHierarchy":"/Finance","baseFolder":"/home/fin","description":"a description","isDefault":true,"edges":[{}],"blockedUntil":null,"blockedBy":"admin","note":"a note","status":"active","fullTarget":"/f","retryCount":0,"default":true,"sendMapping":"m1","receiveMapping":"m2","fileLabelOption":"label","transferMode":"mode","serverEnabled":true,"basicSettings":{"name":"icap1","type":"BOTH","url":"icap://x"},"ldapServers":[{"host":"ldap.example.com","port":389}],"ldapSearches":{"baseDn":"dc=example"},"rules":[{}],"businessUnits":["Finance"],"dateModified":"2026-10-01","operationType":"CREATE","objectType":"Account","objectName":"john","userName":"admin","remoteAddress":"10.0.0.1","time":"t1","level":"INFO","component":"TM","message":"hello","order":1,"className":"VirtClass","userType":"virtual","group":"*","address":"*","enabled":true,"expression":"","subject":"CN=x","expirationTime":1,"usage":"local","connectionType":"local","database":"all","user":"all","authMethod":"md5","serverName":"SSH_TEST","isActive":true,"sshStatus":"Running","banner":"","os":"Linux","version":"5.5-1","serverType":"ST","lastPasswordChangeTime":"x"}
EOF
RULES=$(rules '/subscriptions/obj-1' "${B_ITEM}") GET_BODY="${B_SUPER}" read_check '07.Subscriptions/06' '07.Subscriptions/06.subscriptions_id_GET.sh'

echo
echo "=== 09.CompositeRoutes ==="

expect_calls <<'EOF'
GET @@BASE@@/routes?type=COMPOSITE
GET @@BASE@@/routes?fields=id&name=SimpleRoute_Compress
GET @@BASE@@/routes/obj-1
EOF
expect_out <<'EOF'
The composite routes of 'john': id, name, template, subscriptions...
obj-1  example  template=tpl-1  subscriptions=sub-1

The steps of the simple route 'SimpleRoute_Compress'...
EOF
GET_BODY="${B_SUPER}" read_check '09.CompositeRoutes/06' '09.CompositeRoutes/06.routes_GET.sh'

echo
echo "=== 11.Certificates ==="

expect_calls <<'EOF'
GET @@BASE@@/certificates?limit=1&fields=id
GET @@BASE@@/certificates?usage=partner&type=x509&fields=name,subject,expirationTime
GET @@BASE@@/certificates?usage=partner&expirationTime.from=TS&expirationTime.to=TS&fields=name,account,expirationTime
EOF
expect_out <<'EOF'
Certificates on the server: 7

The x509 partner ones: name, subject, expires:
  example  CN=x  1

The partner ones that expire within 10 days:
  example  john  1
EOF
NORM=1 GET_BODY="${B_SUPER}" read_check '11.Certificates/01' '11.Certificates/01.certificates_GET.sh' 'partner' '10'

expect_calls <<'EOF'
GET @@BASE@@/certificates?name=example&fields=id
GET @@BASE@@/certificates/obj-1
GET @@BASE@@/certificates/obj-1?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint
GET @@BASE@@/certificates/obj-1?includePath=true&fields=name,subject
EOF
expect_out <<'EOF'
{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}

Its SHA256 fingerprint: AB:CD:EF

Its path, from the certificate up:
  example  CN=x
EOF
RULES=$(rules 'includePath' "${B_ARRAY}" 'fingerprint' "${B_FP}" '/certificates/obj-1' "${B_ITEM}") GET_BODY="${B_SUPER}" read_check '11.Certificates/05' '11.Certificates/05.certificates_id_GET.sh' 'example'

expect_calls <<'EOF'
GET @@BASE@@/certificates/requests?fields=id,subject,usage,account
EOF
expect_out <<'EOF'
The requests: id, subject, usage, account:
  obj-1  CN=x  local  john
EOF
GET_BODY="${B_SUPER}" read_check '11.Certificates/10' '11.Certificates/10.certificates_requests_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/certificates/requests?fields=id,subject,usage,account&usage=local
EOF
expect_out <<'EOF'
The requests: id, subject, usage, account:
  obj-1  CN=x  local  john
EOF
GET_BODY="${B_SUPER}" read_check '11.Certificates/10 local' '11.Certificates/10.certificates_requests_GET.sh' 'local'

expect_calls <<'EOF'
GET @@BASE@@/certificates/requests?subject=CN=example_csr,O=Example
GET @@BASE@@/certificates/requests/obj-1
EOF
expect_out <<'EOF'
@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '11.Certificates/12' '11.Certificates/12.certificates_requests_id_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/certificates/requests/req-9
EOF
expect_out <<'EOF'
@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '11.Certificates/12 id' '11.Certificates/12.certificates_requests_id_GET.sh' 'req-9'

echo
echo "=== 12.BusinessUnits ==="

expect_calls <<'EOF'
GET @@BASE@@/businessUnits?limit=5&offset=0
GET @@BASE@@/businessUnits?name=Fin*&fields=businessUnitHierarchy,baseFolder
GET @@BASE@@/businessUnits?parent=Sales&fields=name
EOF
expect_out <<'EOF'
The first 5 business units:
@@BODY@@

The units named Fin*: hierarchy, base folder:
  /Finance  /home/fin

The units nested under Sales:
  example
EOF
GET_BODY="${B_SUPER}" read_check '12.BusinessUnits/02' '12.BusinessUnits/02.businessUnits_GET.sh' 'Fin*' 'Sales'

expect_calls <<'EOF'
GET @@BASE@@/businessUnits?limit=5&offset=0
GET @@BASE@@/businessUnits?name=*&fields=businessUnitHierarchy,baseFolder
EOF
expect_out <<'EOF'
The first 5 business units:
@@BODY@@

The units named *: hierarchy, base folder:
  /Finance  /home/fin
EOF
GET_BODY="${B_SUPER}" read_check '12.BusinessUnits/02 bare' '12.BusinessUnits/02.businessUnits_GET.sh'

echo
echo "=== 13.Configurations ==="

expect_calls <<'EOF'
GET @@BASE@@/configurations/options?limit=1&fields=name
GET @@BASE@@/configurations/options?name=AddressBook*&fields=name,values,defaultValues
GET @@BASE@@/configurations/options?isModified=true&limit=10&fields=name,values
EOF
expect_out <<'EOF'
Server Configuration Options: 7

The options named AddressBook*: name = values (default):
  example = v1 (d1)

The first 10 options changed from their default:
  example = v1
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/03' '13.Configurations/03.configurations_options_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/configurations/options/groups
EOF
expect_out <<'EOF'
The option groups:
  example: a description
EOF
GET_BODY="${B_ARRAY}" read_check '13.Configurations/07' '13.Configurations/07.configurations_options_groups_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/configurations/logging
EOF
expect_out <<'EOF'
Logging options: name, profile, propagation status:
  example  p1  ok
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/09' '13.Configurations/09.configurations_logging_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/configurations/profiles
EOF
expect_out <<'EOF'
Configuration profiles: id, name, protocol, active:
  obj-1  example  ssh  true
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/13' '13.Configurations/13.configurations_profiles_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/configurations/profiles/p1
EOF
expect_out <<'EOF'
@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/15' '13.Configurations/15.configurations_profiles_id_GET.sh' 'p1'

expect_calls <<'EOF'
GET @@BASE@@/configurations/externalStores
EOF
expect_out <<'EOF'
External stores: name, address, cache timeout:
  example  https://vault.example.com/v1  600s
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/37' '13.Configurations/37.configurations_externalStores_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/configurations/externalStores?name=my store
EOF
expect_out <<'EOF'
External stores: name, address, cache timeout:
  example  https://vault.example.com/v1  600s
EOF
GET_BODY="${B_SUPER}" read_check '13.Configurations/37 name' '13.Configurations/37.configurations_externalStores_GET.sh' 'my store'

echo
echo "=== 16.TransferLogs ==="

expect_calls <<'EOF'
GET @@BASE@@/logs/transfers?account=john&sortByStartTime=descending&limit=10
GET @@BASE@@/logs/transfers?account=john&status=Failed&limit=1&fields=id
EOF
expect_out <<'EOF'
The 10 latest transfers of 'john'...
[
  {
    "id": "obj-1",
    "name": "example",
    "loginName": "example_admin",
    "roleName": "Example Role",
    "host": "st.example.com",
    "port": 8022,
    "downloadFolder": "/in",
    "uploadFolder": "/out",
    "folder": "/inbox",
    "application": "AdvancedRoutingApplication",
    "account": "john",
    "accountName": "john",
    "routeTemplate": "tpl-1",
    "subscriptions": [
      "sub-1"
    ],
    "parent": "root",
    "locked": false,
    "menus": [
      "Change Password",
      "Audit Log"
    ],
    "values": [
      "v1"
    ],
    "defaultValues": [
      "d1"
    ],
    "profileId": "p1",
    "propagationStatus": "ok",
    "protocol": "ssh",
    "active": true,
    "baseUrl": "https://vault.example.com",
    "uri": "/v1",
    "cacheTimeout": 600,
    "type": "LOCAL",
    "parentGroup": "g1",
    "businessUnitHierarchy": "/Finance",
    "baseFolder": "/home/fin",
    "description": "a description",
    "isDefault": true,
    "edges": [
      {}
    ],
    "blockedUntil": null,
    "blockedBy": "admin",
    "note": "a note",
    "status": "active",
    "fullTarget": "/f",
    "retryCount": 0,
    "default": true,
    "sendMapping": "m1",
    "receiveMapping": "m2",
    "fileLabelOption": "label",
    "transferMode": "mode",
    "serverEnabled": true,
    "basicSettings": {
      "name": "icap1",
      "type": "BOTH",
      "url": "icap://x"
    },
    "ldapServers": [
      {
        "host": "ldap.example.com",
        "port": 389
      }
    ],
    "ldapSearches": {
      "baseDn": "dc=example"
    },
    "rules": [
      {}
    ],
    "businessUnits": [
      "Finance"
    ],
    "dateModified": "2026-10-01",
    "operationType": "CREATE",
    "objectType": "Account",
    "objectName": "john",
    "userName": "admin",
    "remoteAddress": "10.0.0.1",
    "time": "t1",
    "level": "INFO",
    "component": "TM",
    "message": "hello",
    "order": 1,
    "className": "VirtClass",
    "userType": "virtual",
    "group": "*",
    "address": "*",
    "enabled": true,
    "expression": "",
    "subject": "CN=x",
    "expirationTime": 1,
    "usage": "local",
    "connectionType": "local",
    "database": "all",
    "user": "all",
    "authMethod": "md5",
    "serverName": "SSH_TEST",
    "isActive": true,
    "sshStatus": "Running",
    "banner": "",
    "os": "Linux",
    "version": "5.5-1",
    "serverType": "ST",
    "lastPasswordChangeTime": "x"
  }
]
7 transfer(s) of 'john' in the log, in all.

How many of them failed...
7 failed transfer(s).
EOF
GET_BODY="${B_SUPER}" read_check '16.TransferLogs/01' '16.TransferLogs/01.logs_transfers_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/logs/transfers?account=alice&sortByStartTime=descending&limit=10
GET @@BASE@@/logs/transfers?account=alice&status=Failed&limit=1&fields=id
EOF
expect_out <<'EOF'
The 10 latest transfers of 'alice'...
[
  {
    "id": "obj-1",
    "name": "example",
    "loginName": "example_admin",
    "roleName": "Example Role",
    "host": "st.example.com",
    "port": 8022,
    "downloadFolder": "/in",
    "uploadFolder": "/out",
    "folder": "/inbox",
    "application": "AdvancedRoutingApplication",
    "account": "john",
    "accountName": "john",
    "routeTemplate": "tpl-1",
    "subscriptions": [
      "sub-1"
    ],
    "parent": "root",
    "locked": false,
    "menus": [
      "Change Password",
      "Audit Log"
    ],
    "values": [
      "v1"
    ],
    "defaultValues": [
      "d1"
    ],
    "profileId": "p1",
    "propagationStatus": "ok",
    "protocol": "ssh",
    "active": true,
    "baseUrl": "https://vault.example.com",
    "uri": "/v1",
    "cacheTimeout": 600,
    "type": "LOCAL",
    "parentGroup": "g1",
    "businessUnitHierarchy": "/Finance",
    "baseFolder": "/home/fin",
    "description": "a description",
    "isDefault": true,
    "edges": [
      {}
    ],
    "blockedUntil": null,
    "blockedBy": "admin",
    "note": "a note",
    "status": "active",
    "fullTarget": "/f",
    "retryCount": 0,
    "default": true,
    "sendMapping": "m1",
    "receiveMapping": "m2",
    "fileLabelOption": "label",
    "transferMode": "mode",
    "serverEnabled": true,
    "basicSettings": {
      "name": "icap1",
      "type": "BOTH",
      "url": "icap://x"
    },
    "ldapServers": [
      {
        "host": "ldap.example.com",
        "port": 389
      }
    ],
    "ldapSearches": {
      "baseDn": "dc=example"
    },
    "rules": [
      {}
    ],
    "businessUnits": [
      "Finance"
    ],
    "dateModified": "2026-10-01",
    "operationType": "CREATE",
    "objectType": "Account",
    "objectName": "john",
    "userName": "admin",
    "remoteAddress": "10.0.0.1",
    "time": "t1",
    "level": "INFO",
    "component": "TM",
    "message": "hello",
    "order": 1,
    "className": "VirtClass",
    "userType": "virtual",
    "group": "*",
    "address": "*",
    "enabled": true,
    "expression": "",
    "subject": "CN=x",
    "expirationTime": 1,
    "usage": "local",
    "connectionType": "local",
    "database": "all",
    "user": "all",
    "authMethod": "md5",
    "serverName": "SSH_TEST",
    "isActive": true,
    "sshStatus": "Running",
    "banner": "",
    "os": "Linux",
    "version": "5.5-1",
    "serverType": "ST",
    "lastPasswordChangeTime": "x"
  }
]
7 transfer(s) of 'alice' in the log, in all.

How many of them failed...
7 failed transfer(s).
EOF
GET_BODY="${B_SUPER}" read_check '16.TransferLogs/01 alice' '16.TransferLogs/01.logs_transfers_GET.sh' 'alice'

echo
echo "=== 17.AccessPolicies ==="

expect_calls <<'EOF'
GET @@BASE@@/accessPolicies
GET @@BASE@@/accessPolicies?fields=id,connectionType,database,user,address,authMethod
EOF
expect_out <<'EOF'
Every database access policy, in the order they are read:
@@BODY@@

The same, one line each: id, connection type, database, user, address, method:
  obj-1  local  all  all  *  md5
EOF
GET_BODY="${B_ARRAY}" read_check '17.AccessPolicies/01' '17.AccessPolicies/01.accessPolicies_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/accessPolicies/2
GET @@BASE@@/accessPolicies/2?fields=database,user,authMethod
EOF
expect_out <<'EOF'
Rule 2:
@@BODY@@

Only its database, user and method:
@@BODY@@
EOF
GET_BODY="${B_ARRAY}" read_check '17.AccessPolicies/04' '17.AccessPolicies/04.accessPolicies_id_GET.sh' '2'

echo
echo "=== 19.AddressBook ==="

expect_calls <<'EOF'
GET @@BASE@@/addressBook/sources
GET @@BASE@@/addressBook/sources?type=LDAP
GET @@BASE@@/addressBook/sources?enabled=true&fields=id,type,name,parentGroup
EOF
expect_out <<'EOF'
Every address book source:
@@BODY@@

The LDAP sources only:
@@BODY@@

The enabled ones, one line each: id, type, name, group:
  obj-1  LOCAL  example  g1
EOF
GET_BODY="${B_SUPER}" read_check '19.AddressBook/01' '19.AddressBook/01.addressBook_sources_GET.sh'

expect_calls <<'EOF'
GET @@BASE@@/addressBook/sources?name=LDAP&fields=id
GET @@BASE@@/addressBook/sources/obj-1
GET @@BASE@@/addressBook/sources/obj-1?fields=customProperties
EOF
expect_out <<'EOF'
The source LDAP:
@@BODY@@

Only its custom properties:
@@BODY@@
EOF
GET_BODY="${B_SUPER}" read_check '19.AddressBook/03' '19.AddressBook/03.addressBook_sources_id_GET.sh'

echo
echo "=== 20.AdministrativeRoles ==="

expect_calls <<'EOF'
GET @@BASE@@/administrativeRoles?limit=5&offset=0
GET @@BASE@@/administrativeRoles?isLimited=true&fields=roleName,menus
EOF
expect_out <<'EOF'
The first 5 roles:
@@BODY@@

The limited roles, one line each: name, the menus they open:
  Example Role: Change Password, Audit Log
EOF
GET_BODY="${B_SUPER}" read_check '20.AdministrativeRoles/01' '20.AdministrativeRoles/01.administrativeRoles_GET.sh'

echo
echo "=== 21.Administrators ==="

expect_calls <<'EOF'
GET @@BASE@@/administrators?limit=5&offset=0&fields=loginName,roleName
GET @@BASE@@/administrators?roleName=Example Role&fields=loginName,parent,locked
GET @@BASE@@/administrators?locked=true&fields=loginName
EOF
expect_out <<'EOF'
The first 5 administrators, login name and role:
@@BODY@@

The ones that hold Example Role:
  example_admin  created by root

The locked ones:
  example_admin
EOF
GET_BODY="${B_SUPER}" read_check '21.Administrators/01' '21.Administrators/01.administrators_GET.sh' 'Example Role'

echo
echo "=== 22.DeniedUsers ==="

expect_calls <<'EOF'
GET @@BASE@@/deniedUsers?limit=1&fields=loginName
GET @@BASE@@/deniedUsers?loginName=*
GET @@BASE@@/deniedUsers?loginName=*&isPermanent=true
GET @@BASE@@/deniedUsers?loginName=*&isPermanent=false
GET @@BASE@@/deniedUsers?loginName=*&blockedAt.from=2026-01-01
EOF
expect_out <<'EOF'
Denied users: 7

The login names matching *: name, until, by, note:
  example_admin  permanent  by admin  a note

Only the permanent ones:
  example_admin  permanent  by admin  a note

Only the temporary ones:
  example_admin  permanent  by admin  a note

Blocked on or after 2026-01-01:
  example_admin  permanent  by admin  a note
EOF
GET_BODY="${B_SUPER}" read_check '22.DeniedUsers/01' '22.DeniedUsers/01.deniedUsers_GET.sh' '*' '2026-01-01'

echo
echo "=== 23.Events ==="

expect_calls <<'EOF'
GET @@BASE@@/events?limit=1&fields=id
GET @@BASE@@/events?accountName=john*&status=active
GET @@BASE@@/events?accountName=john*&processorType=ADVANCED_ROUTING
GET @@BASE@@/events?accountName=john*&lastHeartbeatAfter=TS
EOF
expect_out <<'EOF'
Events: 7

The events of the accounts matching john*: id, status, account, file, retries:
  obj-1  active  john  /f  retries 0

Only the Advanced Routing ones:
  obj-1  active  john  /f  retries 0

With a heartbeat in the last hour:
  obj-1  active  john  /f  retries 0
EOF
NORM=1 GET_BODY="${B_SUPER}" read_check '23.Events/01' '23.Events/01.events_GET.sh' 'john*' 'active'

echo
echo "=== 24.IcapServers ==="

expect_calls <<'EOF'
GET @@BASE@@/icapServers?limit=1&fields=serverEnabled
GET @@BASE@@/icapServers?fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url
GET @@BASE@@/icapServers?serverEnabled=true&fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url
GET @@BASE@@/icapServers?basicSettings.name=icap1&fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url
GET @@BASE@@/icapServers?basicSettings.type=BOTH&fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url
EOF
expect_out <<'EOF'
ICAP servers: 7

All of them: name, type, address, enabled:
  icap1  BOTH  icap://x  enabled

Only the enabled ones:
  icap1  BOTH  icap://x  enabled

The one named icap1:
  icap1  BOTH  icap://x  enabled

Only the ones of type BOTH:
  icap1  BOTH  icap://x  enabled
EOF
GET_BODY="${B_SUPER}" read_check '24.IcapServers/01' '24.IcapServers/01.icapServers_GET.sh' 'icap1' 'BOTH'

echo
echo "=== 25.LdapDomains ==="

expect_calls <<'EOF'
GET @@BASE@@/ldapDomains?limit=1&fields=name
GET @@BASE@@/ldapDomains?fields=name,ldapServers,ldapSearches.baseDn,isDefault
GET @@BASE@@/ldapDomains?name=dom&fields=name,ldapServers,ldapSearches.baseDn,isDefault
GET @@BASE@@/ldapDomains?protocolVersion=3&fields=name,ldapServers,ldapSearches.baseDn,isDefault
EOF
expect_out <<'EOF'
LDAP domains: 7

All of them: name, servers, base DN, default:
  example  ldap.example.com:389  dc=example  default

The one named dom:
  example  ldap.example.com:389  dc=example  default

Only the ones using LDAP version 3:
  example  ldap.example.com:389  dc=example  default
EOF
GET_BODY="${B_SUPER}" read_check '25.LdapDomains/01' '25.LdapDomains/01.ldapDomains_GET.sh' 'dom' '3'

echo
echo "=== 26.LoginRestrictionPolicies ==="

expect_calls <<'EOF'
GET @@BASE@@/loginRestrictionPolicies?limit=1&fields=name
GET @@BASE@@/loginRestrictionPolicies?name=*&fields=name,type,isDefault,rules,businessUnit
GET @@BASE@@/loginRestrictionPolicies?type=ALLOW_THEN_DENY&fields=name,type,isDefault,rules,businessUnit
GET @@BASE@@/loginRestrictionPolicies?isDefault=true&fields=name,type,isDefault,rules,businessUnit
EOF
expect_out <<'EOF'
Login restriction policies: 7

The policies named *: name, type, rules, business units:
  example  LOCAL  1 rule(s)  default  business units: Finance

Only the ones of type ALLOW_THEN_DENY:
  example  LOCAL  1 rule(s)  default  business units: Finance

The default policy, which applies to every account that has none of its own:
  example  LOCAL  1 rule(s)  default  business units: Finance
EOF
GET_BODY="${B_SUPER}" read_check '26.LoginRestrictionPolicies/01' '26.LoginRestrictionPolicies/01.loginRestrictionPolicies_GET.sh' '*' 'ALLOW_THEN_DENY'

echo
echo "=== 27.AuditLogs ==="

expect_calls <<'EOF'
GET @@BASE@@/logs/audit?limit=1&fields=id
GET @@BASE@@/logs/audit?duration=5&limit=1&fields=id
GET @@BASE@@/logs/audit?duration=5&limit=5&fields=id,dateModified,operationType,objectType,objectName,userName,remoteAddress
GET @@BASE@@/logs/audit?objectType=Account&objectName=john&operationType=CREATE&limit=10&fields=id,dateModified,operationType,objectType,objectName,userName,remoteAddress
EOF
expect_out <<'EOF'
Audit log entries: 7

The last 5 hour(s): 7 entries
The latest 5, newest first:
  2026-10-01  CREATE  Account john  by admin from 10.0.0.1

The latest 10 entries for those filters:
  2026-10-01  CREATE  Account john  by admin from 10.0.0.1
EOF
GET_BODY="${B_SUPER}" read_check '27.AuditLogs/01' '27.AuditLogs/01.logs_audit_GET.sh' '5' 'Account' 'john' 'CREATE'

echo
echo "=== 28.ServerLogs ==="

expect_calls <<'EOF'
GET @@BASE@@/logs/server?fromDate=DATE&limit=1&fields=id
GET @@BASE@@/logs/server?fromDate=DATE&message=hello&component=TM&component=SSHD&level=INFO&limit=20&fields=time,level,component,message
EOF
expect_out <<'EOF'
Server log entries since DATE: 7

The first 20 that match the filters: time, level, component, message:
  t1  INFO  TM  hello
EOF
NORM=1 GET_BODY="${B_SUPER}" read_check '28.ServerLogs/01' '28.ServerLogs/01.logs_server_GET.sh' '5' 'hello' 'TM,SSHD' 'INFO'

echo
echo "=== 29.MailTemplates ==="

expect_calls <<'EOF'
GET @@BASE@@/mailTemplates?limit=1&fields=name
GET @@BASE@@/mailTemplates?limit=100
GET @@BASE@@/mailTemplates?name=a.xhtml
GET @@BASE@@/mailTemplates?description=d
EOF
expect_out <<'EOF'
Mail templates: 7

All of them: name, description:
  example  a description

Named a.xhtml:
  example  a description

Described as d:
  example  a description
EOF
GET_BODY="${B_SUPER}" read_check '29.MailTemplates/01' '29.MailTemplates/01.mailTemplates_GET.sh' 'a.xhtml' 'd'

echo
echo "=== 35.TransferProfiles ==="

expect_calls <<'EOF'
GET @@BASE@@/transferProfiles?limit=1&fields=id
GET @@BASE@@/transferProfiles?account=acct&name=P*
GET @@BASE@@/transferProfiles?account=acct&name=P*&default=true
EOF
expect_out <<'EOF'
Transfer profiles on the server: 7

The profiles matching P*: id, account/name, default, mappings, file label, mode:
  obj-1  john/example  default  send m1  receive m2  label  mode

Only the default ones:
  obj-1  john/example  default  send m1  receive m2  label  mode
EOF
GET_BODY="${B_SUPER}" read_check '35.TransferProfiles/01' '35.TransferProfiles/01.transferProfiles_GET.sh' 'acct' 'P*'

expect_calls <<'EOF'
GET @@BASE@@/transferProfiles?account=acct&name=example&fields=id,name
GET @@BASE@@/transferProfiles/obj-1
GET @@BASE@@/transferProfiles/obj-1?fields=name,sendMapping,receiveMapping
EOF
expect_out <<'EOF'
The transfer profile example of acct, id obj-1:
  default:     true
  send:        m1
  receive:     m2
  file label:  label
  mode:        mode, null records of null
  acknowledge: null
  advanced:    null

Only some fields of it:
{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}
EOF
RULES=$(rules '/transferProfiles/obj-1' "${B_ITEM}") GET_BODY="${B_SUPER}" read_check '35.TransferProfiles/04' '35.TransferProfiles/04.transferProfiles_id_GET.sh' 'acct' 'example'

echo
echo "=== 36.UserClasses ==="

expect_calls <<'EOF'
GET @@BASE@@/userClasses?limit=1&fields=id
GET @@BASE@@/userClasses?userType=virtual&className=VirtClass&limit=1000
GET @@BASE@@/userClasses?userType=virtual&className=VirtClass&limit=1000&enabled=true
EOF
expect_out <<'EOF'
User classes on the server: 7

The classes matching VirtClass, in the order they are tried: order, name, type, user, group, address, state, expression:
  1  VirtClass  virtual  user admin  group *  address *  enabled  expression -

Only the enabled ones:
  1  VirtClass  virtual  user admin  group *  address *  enabled  expression -
EOF
GET_BODY="${B_SUPER}" read_check '36.UserClasses/01' '36.UserClasses/01.userClasses_GET.sh' 'VirtClass' 'virtual'

expect_calls <<'EOF'
GET @@BASE@@/userClasses?className=VirtClass&fields=id,className
GET @@BASE@@/userClasses/obj-1
GET @@BASE@@/userClasses/obj-1?fields=className,enabled
EOF
expect_out <<'EOF'
The user class VirtClass, id obj-1:
  order:      1
  type:       virtual
  user name:  admin
  group:      *
  address:    *
  enabled:    true
  expression: -

Only some fields of it:
{"id": "obj-1", "name": "example", "loginName": "example_admin", "roleName": "Example Role", "host": "st.example.com", "port": 8022, "downloadFolder": "/in", "uploadFolder": "/out", "folder": "/inbox", "application": "AdvancedRoutingApplication", "account": "john", "accountName": "john", "routeTemplate": "tpl-1", "subscriptions": ["sub-1"], "parent": "root", "locked": false, "menus": ["Change Password", "Audit Log"], "values": ["v1"], "defaultValues": ["d1"], "profileId": "p1", "propagationStatus": "ok", "protocol": "ssh", "active": true, "baseUrl": "https://vault.example.com", "uri": "/v1", "cacheTimeout": 600, "type": "LOCAL", "parentGroup": "g1", "businessUnitHierarchy": "/Finance", "baseFolder": "/home/fin", "description": "a description", "isDefault": true, "edges": [{}], "blockedUntil": null, "blockedBy": "admin", "note": "a note", "status": "active", "fullTarget": "/f", "retryCount": 0, "default": true, "sendMapping": "m1", "receiveMapping": "m2", "fileLabelOption": "label", "transferMode": "mode", "serverEnabled": true, "basicSettings": {"name": "icap1", "type": "BOTH", "url": "icap://x"}, "ldapServers": [{"host": "ldap.example.com", "port": 389}], "ldapSearches": {"baseDn": "dc=example"}, "rules": [{}], "businessUnits": ["Finance"], "dateModified": "2026-10-01", "operationType": "CREATE", "objectType": "Account", "objectName": "john", "userName": "admin", "remoteAddress": "10.0.0.1", "time": "t1", "level": "INFO", "component": "TM", "message": "hello", "order": 1, "className": "VirtClass", "userType": "virtual", "group": "*", "address": "*", "enabled": true, "expression": "", "subject": "CN=x", "expirationTime": 1, "usage": "local", "connectionType": "local", "database": "all", "user": "all", "authMethod": "md5", "serverName": "SSH_TEST", "isActive": true, "sshStatus": "Running", "banner": "", "os": "Linux", "version": "5.5-1", "serverType": "ST", "lastPasswordChangeTime": "x"}
EOF
RULES=$(rules '/userClasses/obj-1' "${B_ITEM}") GET_BODY="${B_SUPER}" read_check '36.UserClasses/04' '36.UserClasses/04.userClasses_id_GET.sh' 'VirtClass'

echo
echo "=== 37.Zones ==="

expect_calls <<'EOF'
GET @@BASE@@/zones?limit=1&fields=name
GET @@BASE@@/zones?name=My zone&limit=1000
GET @@BASE@@/zones?isDefault=true&limit=1000
EOF
expect_out <<'EOF'
Zones on the server: 7

The zones named My zone: name, default, edges, description:

The default zone:
  example  default true  edges 1  a description
EOF
GET_BODY="${B_SUPER}" read_check '37.Zones/01' '37.Zones/01.zones_GET.sh' 'My zone'

# ==============================================================================
# The particular ones
# ==============================================================================
echo
echo "=== 01.Authentication: the login is a POST ==="
LOGIN=$(body login '{"message": "Logged in"}')
ST_POST=200 POST_BODY="${LOGIN}" run 01.Authentication/01.myself_POST.sh
expect "01 myself_POST: sends a POST /myself, as its name says, and nothing else" "${RC}:$(calls)" "0:POST ${BASE}/myself"
has "01 myself_POST: prints the answer of the login" '{"message": "Logged in"}'
expect "01 myself_POST: the login carries the Referer and no csrfToken" "$(echoed 'HEADER: Referer: THIS_IS_A_RANDOM_TEXT'):$(echoed 'csrfToken')" "1:0"
ST_POST=401 POST_BODY="${B_401}" run 01.Authentication/01.myself_POST.sh
expect "01 myself_POST: a refused login is exit 1, with its status and the answer" "${RC}:$(printf '%s' "${OUT}" | grep -c 'HTTP 401'):$(printf '%s' "${OUT}" | grep -c 'Authentication required.')" "1:1:1"
ST_POST=500 POST_BODY="${B_500}" run 01.Authentication/01.myself_POST.sh
expect "01 myself_POST: a 500 is exit 1" "${RC}" "1"

# 01.myself_cookie_POST: the login, then the read with the jar and the token
mkdir -p "${WORK}/admin/01.Authentication"
: > "${WORK}/admin/01.Authentication/cookie.jar"
CSRF=tok-7 ST_POST=200 POST_BODY="${LOGIN}" GET_BODY="${B_PLAIN}" run 01.Authentication/01.myself_cookie_POST.sh
expect "01 cookie: a login, then a read" "${RC}:$(calls)" "0:POST ${BASE}/myself
GET ${BASE}/myself"
expect "01 cookie: the login keeps the session in the jar" "$(echoed 'COOKIE_JAR_WRITE: cookie.jar')" "1"
expect "01 cookie: the read sends the jar and the csrfToken of the login" "$(echoed 'COOKIE: cookie.jar'):$(echoed 'HEADER: csrfToken: tok-7')" "1:1"
expect "01 cookie: the jar is left for the next call, as before" "$(test -f "${WORK}/admin/01.Authentication/cookie.jar" && echo yes)" "yes"
expect "01 cookie: the temporary header file is removed" "$(ls "${WORK}/tmp" | wc -l | tr -d ' ')" "0"
has "01 cookie: prints the answer of the login" '{"message": "Logged in"}'
has "01 cookie: and the answer of the read" '"loginName": "admin"'
ST_POST=401 POST_BODY="${B_401}" run 01.Authentication/01.myself_cookie_POST.sh
expect "01 cookie: a refused login is exit 1, with one call" "${RC}:$(ncalls)" "1:1"
has "01 cookie: and says why" "HTTP 401"
expect "01 cookie: and removes the jar, which holds no session" "$(test -f "${WORK}/admin/01.Authentication/cookie.jar" && echo yes || echo no)" "no"
expect "01 cookie: and the temporary header file too" "$(ls "${WORK}/tmp" | wc -l | tr -d ' ')" "0"
: > "${WORK}/admin/01.Authentication/cookie.jar"
ST_POST=200 POST_BODY="${LOGIN}" ST_GET=500 GET_BODY="${B_500}" run 01.Authentication/01.myself_cookie_POST.sh
expect "01 cookie: a read that is refused is exit 1" "${RC}:$(ncalls)" "1:2"
has "01 cookie: with its status" "HTTP 500"
rm -f "${WORK}/admin/01.Authentication/cookie.jar"

echo
echo "=== 02.Introduction ==="
# the answers as the server writes them, one field to a line
VERSION_5_5=$(body version55 '{
  "serverType" : "ST-Core-Server",
  "version" : "5.5-20260924",
  "os" : "Linux",
  "osDistribution" : "Example Linux 9"
}')
VERSION_5_4=$(body version54 '{
  "serverType" : "ST-Core-Server",
  "version" : "5.4-20240101",
  "build" : "1"
}')
GET_BODY="${VERSION_5_5}" run 02.Introduction/02.version_GET.sh
expect "02 version: exit 0" "${RC}" "0"
expect "02 version: each grep prints its lines" "$(printf '%s\n' "${OUT}" | grep -c '"version" : "5.5-20260924"')" "2"
expect "02 version: grep os finds os and osDistribution" "$(printf '%s\n' "${OUT}" | grep -c '"os')" "2"
GET_BODY="${VERSION_5_4}" run 02.Introduction/02.version_GET.sh
expect "02 version: a server that is not 5.5, with no line for the greps, is exit 0 all the same: the exit code is the call's" "${RC}" "0"
has "02 version: it still says what it looked for" "grep for version.*5.5..."
ST_GET=401 GET_BODY="${B_401}" run 02.Introduction/02.version_GET.sh
expect "02 version: a refused read is exit 1, and nothing is grepped" "${RC}:$(printf '%s' "${OUT}" | grep -c 'grep for')" "1:0"
NO_PWD=$(body no_pwd '{"loginName": "admin"}')
GET_BODY="${NO_PWD}" run 02.Introduction/03.myself_GET.sh
expect "03 myself: an answer without lastPasswordChangeTime is exit 0: the exit code is the calls', not the grep's" "${RC}:$(ncalls)" "0:2"
ST_GET=401 GET_BODY="${B_401}" run 02.Introduction/03.myself_GET.sh
expect "03 myself: a refused first read is exit 1, after one call" "${RC}:$(ncalls)" "1:1"
GET_BODY="${NO_PWD}" ST_GET_SEQ="200 401" run 02.Introduction/03.myself_GET.sh
expect "03 myself: a refused second read is exit 1 too" "${RC}:$(ncalls)" "1:2"

echo "  -- 06.myself_DELETE: log in, read, log out, and the read after it is refused"
LOGOUT=$(body logout '{"message": "Logged out"}')
S=02.Introduction/06.myself_DELETE.sh
mkdir -p "${WORK}/admin/02.Introduction"
CSRF=tok-9 ST_POST=200 POST_BODY="${LOGIN}" ST_DELETE=200 ERR_BODY="${LOGOUT}" ST_GET_SEQ="200 401" GET_BODY="${B_PLAIN}" run "${S}"
expect "06: login, read, logout, read, in that order" "${RC}:$(calls)" "0:POST ${BASE}/myself
GET ${BASE}/myself
DELETE ${BASE}/myself
GET ${BASE}/myself"
expect "06: the three calls after the login send the jar and the token of the login" "$(echoed 'COOKIE: cookie.jar'):$(echoed 'HEADER: csrfToken: tok-9')" "3:3"
expect "06: the temporary header file is removed" "$(ls "${WORK}/tmp" | wc -l | tr -d ' ')" "0"
CSRF=tok-9 ST_POST=200 POST_BODY="${LOGIN}" ST_DELETE=200 ERR_BODY="${LOGOUT}" ST_GET_SEQ="200 403" GET_BODY="${B_PLAIN}" run "${S}"
expect "06: a 403 after the logout is a session that ended too" "${RC}" "0"
CSRF=tok-9 ST_POST=200 POST_BODY="${LOGIN}" ST_DELETE=200 ERR_BODY="${LOGOUT}" ST_GET_SEQ="200 200" GET_BODY="${B_PLAIN}" run "${S}"
expect "06: a read that still answers 200 after the logout is exit 1" "${RC}" "1"
has "06: and says the session is still open" "The session is still open: HTTP 200"
CSRF=tok-9 ST_POST=200 POST_BODY="${LOGIN}" ST_DELETE=500 ERR_BODY="${B_500}" ST_GET_SEQ="200" GET_BODY="${B_PLAIN}" run "${S}"
expect "06: a logout that is refused is exit 1, and the last read is not made" "${RC}:$(ncalls)" "1:3"
has "06: with its status" "HTTP 500"
CSRF=tok-9 ST_POST=200 POST_BODY="${LOGIN}" ST_GET_SEQ="401" GET_BODY="${B_401}" run "${S}"
expect "06: a first read that is refused is exit 1, and nothing is logged out" "${RC}:$(ncalls)" "1:2"
ST_POST=401 POST_BODY="${B_401}" run "${S}"
expect "06: a refused login is exit 1 after one call" "${RC}:$(ncalls)" "1:1"
expect "06: and leaves no jar" "$(test -f "${WORK}/admin/02.Introduction/cookie.jar" && echo yes || echo no)" "no"

echo
echo "=== 03.Connect: the HEAD of a server, and a GET of one that is not there ==="
S=03.Connect/08.servers_name_HEAD.sh
ST_HEAD=200 run "${S}"
expect "08 HEAD: a server that is there: exit 0, and says so" "${RC}:$(printf '%s' "${OUT}" | grep -c '^Server exists.$')" "0:1"
expect "08 HEAD: two HEADs, the headers and the code, of the same server" "$(calls)" "HEAD ${BASE}/servers/SSH_TEST_SERVER_1
HEAD ${BASE}/servers/SSH_TEST_SERVER_1"
for st in 400 404; do
    ST_HEAD="${st}" run "${S}"
    expect "08 HEAD: the lab answers a HEAD of a missing server with ${st} and no body: exit 1" "${RC}" "1"
    has "08 HEAD: ${st}: says the server does not exist, with the status" "Server does not exist. HTTP ${st}"
done
for st in 401 500; do
    ST_HEAD="${st}" run "${S}"
    expect "08 HEAD: ${st} is not a missing server: exit 1" "${RC}" "1"
    has "08 HEAD: ${st}: says the check could not be made, with the status" "Could not check the server. HTTP ${st}"
    hasnt "08 HEAD: ${st}: does not claim the server is missing" "Server does not exist."
done
NOT_FOUND=$(body not_found '<!doctype html><html><head><title>HTTP Status 404 – Not Found</title></head><body><h1>HTTP Status 404 – Not Found</h1></body></html>')
ST_GET=404 GET_BODY="${NOT_FOUND}" run 03.Connect/09.servers_name_GET.sh
expect "09 GET: a server that is not there is a 404 with an HTML page: exit 1 after one call" "${RC}:$(ncalls)" "1:1"
has "09 GET: with the status" "HTTP 404"
has "09 GET: and the page" "Not Found"
ST_GET_SEQ="200 404" GET_BODY="${B_PLAIN}" run 03.Connect/09.servers_name_GET.sh
expect "09 GET: the second read refused is exit 1 too" "${RC}:$(ncalls)" "1:2"

echo
echo "=== Arguments: a wrong one, or one too many, is exit 2 and nothing is sent ==="
bad_args 11.Certificates/10.certificates_requests_GET.sh nonsense
bad_args 11.Certificates/10.certificates_requests_GET.sh Local
bad_args 11.Certificates/10.certificates_requests_GET.sh local private
GET_BODY="${B_SUPER}" run 11.Certificates/10.certificates_requests_GET.sh private
expect "11/10: private is a usage" "${RC}:$(calls)" "0:GET ${BASE}/certificates/requests?fields=id,subject,usage,account&usage=private"
bad_args 11.Certificates/01.certificates_GET.sh ca
bad_args 11.Certificates/01.certificates_GET.sh server 5
bad_args 11.Certificates/01.certificates_GET.sh local x
bad_args 11.Certificates/01.certificates_GET.sh local 5 extra
GET_BODY="${B_SUPER}" run 11.Certificates/01.certificates_GET.sh trusted 5
expect "11/01: trusted is a usage" "$(calls | sed -n 2p)" "GET ${BASE}/certificates?usage=trusted&type=x509&fields=name,subject,expirationTime"
bad_args 12.BusinessUnits/02.businessUnits_GET.sh a b c
bad_args 13.Configurations/03.configurations_options_GET.sh a b
bad_args 13.Configurations/37.configurations_externalStores_GET.sh a b
bad_args 16.TransferLogs/01.logs_transfers_GET.sh a b
bad_args 16.TransferLogs/02.logs_transfers_GET_billable.sh x
bad_args 16.TransferLogs/02.logs_transfers_GET_billable.sh 0
bad_args 16.TransferLogs/02.logs_transfers_GET_billable.sh 3 john extra
bad_args 21.Administrators/01.administrators_GET.sh a b
bad_args 22.DeniedUsers/01.deniedUsers_GET.sh '*' 2026-1-1
bad_args 22.DeniedUsers/01.deniedUsers_GET.sh '*' 2026-01-01 extra
bad_args 23.Events/01.events_GET.sh a b c
bad_args 24.IcapServers/01.icapServers_GET.sh a Both
bad_args 24.IcapServers/01.icapServers_GET.sh a BOTH c
bad_args 25.LdapDomains/01.ldapDomains_GET.sh a 4
bad_args 25.LdapDomains/01.ldapDomains_GET.sh a 3 c
bad_args 26.LoginRestrictionPolicies/01.loginRestrictionPolicies_GET.sh '*' ALLOW
bad_args 26.LoginRestrictionPolicies/01.loginRestrictionPolicies_GET.sh '*' ALLOW_THEN_DENY c
bad_args 27.AuditLogs/01.logs_audit_GET.sh 0
bad_args 27.AuditLogs/01.logs_audit_GET.sh 5 t n SELECT
bad_args 27.AuditLogs/01.logs_audit_GET.sh 5 t n CREATE extra
bad_args 28.ServerLogs/01.logs_server_GET.sh 0
bad_args 28.ServerLogs/01.logs_server_GET.sh 5 m NOPE
bad_args 28.ServerLogs/01.logs_server_GET.sh 5 m TM loud
bad_args 28.ServerLogs/01.logs_server_GET.sh 5 m TM INFO extra
bad_args 29.MailTemplates/01.mailTemplates_GET.sh a b c
bad_args 35.TransferProfiles/01.transferProfiles_GET.sh a b c
bad_args 36.UserClasses/01.userClasses_GET.sh a any extra
bad_args 36.UserClasses/01.userClasses_GET.sh a nonsense
bad_args 37.Zones/01.zones_GET.sh a b
bad_args 06.TransferSites/06.sites_id_GET.sh a b c
bad_args 07.Subscriptions/06.subscriptions_id_GET.sh a b c d
bad_args 11.Certificates/05.certificates_id_GET.sh a b
bad_args 11.Certificates/12.certificates_requests_id_GET.sh a b
bad_args 13.Configurations/15.configurations_profiles_id_GET.sh a b
bad_args 17.AccessPolicies/04.accessPolicies_id_GET.sh 1 2
bad_args 19.AddressBook/03.addressBook_sources_id_GET.sh a b
bad_args 35.TransferProfiles/04.transferProfiles_id_GET.sh a b c
bad_args 36.UserClasses/04.userClasses_id_GET.sh a b

echo
echo "=== The scripts that look an object up, then read it: any of their reads refused is exit 1 ==="
# refused_at LABEL N FOLDER/SCRIPT ARGS...: the first N-1 calls answer 200 and the Nth answers 500; GET_BODY is the good answer
RULE_LIST=$(body rule_list '[{"id":7,"database":"example_db","user":"example_user"}]')
refused_at() {
    local label="$1" n="$2" rel="$3" seq="" i; shift 3
    for i in $(seq 1 $((n - 1))); do seq="${seq}200 "; done
    ST_GET_SEQ="${seq}500" ERR_BODY="${B_500}" run "${rel}" "$@"
    expect "${label}: call ${n} refused is exit 1, after ${n} calls" "${RC}:$(ncalls)" "1:${n}"
    has "${label}: call ${n} refused says HTTP 500" "HTTP 500"
}
RULES=$(rules "/sites/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "06/06" 2 06.TransferSites/06.sites_id_GET.sh john example
RULES=$(rules "/sites/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "06/06" 3 06.TransferSites/06.sites_id_GET.sh john example
RULES=$(rules "/subscriptions/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "07/06" 2 07.Subscriptions/06.subscriptions_id_GET.sh
RULES=$(rules "/subscriptions/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "07/06" 3 07.Subscriptions/06.subscriptions_id_GET.sh
RULES=$(rules "includePath" "${B_ARRAY}" "fingerprint" "${B_FP}" "/certificates/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "11/05" 2 11.Certificates/05.certificates_id_GET.sh example
RULES=$(rules "includePath" "${B_ARRAY}" "fingerprint" "${B_FP}" "/certificates/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "11/05" 3 11.Certificates/05.certificates_id_GET.sh example
RULES=$(rules "includePath" "${B_ARRAY}" "fingerprint" "${B_FP}" "/certificates/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "11/05" 4 11.Certificates/05.certificates_id_GET.sh example
GET_BODY="${B_SUPER}" refused_at "11/12" 2 11.Certificates/12.certificates_requests_id_GET.sh
GET_BODY="${B_SUPER}" refused_at "19/03" 2 19.AddressBook/03.addressBook_sources_id_GET.sh
GET_BODY="${B_SUPER}" refused_at "19/03" 3 19.AddressBook/03.addressBook_sources_id_GET.sh
GET_BODY="${B_ARRAY}" refused_at "17/04" 2 17.AccessPolicies/04.accessPolicies_id_GET.sh 2
RULES=$(rules "/accessPolicies/" "${B_ITEM}") GET_BODY="${RULE_LIST}" refused_at "17/04" 3 17.AccessPolicies/04.accessPolicies_id_GET.sh
RULES=$(rules "/transferProfiles/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "35/04" 2 35.TransferProfiles/04.transferProfiles_id_GET.sh acct example
RULES=$(rules "/transferProfiles/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "35/04" 3 35.TransferProfiles/04.transferProfiles_id_GET.sh acct example
RULES=$(rules "/userClasses/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "36/04" 2 36.UserClasses/04.userClasses_id_GET.sh VirtClass
RULES=$(rules "/userClasses/obj-1" "${B_ITEM}") GET_BODY="${B_SUPER}" refused_at "36/04" 3 36.UserClasses/04.userClasses_id_GET.sh VirtClass
# the profile of the server's own configuration is looked up when no id is given
PROFILES=$(body profiles '{"result":[{"id":"-1","name":"Other"},{"id":"-645867027","name":"SecureTransport Server Configuration"}]}')
GET_BODY="${PROFILES}" run 13.Configurations/15.configurations_profiles_id_GET.sh
expect "13/15: with no id, the profile of the server is looked up, then read" "${RC}:$(calls)" "0:GET ${BASE}/configurations/profiles
GET ${BASE}/configurations/profiles/-645867027"
GET_BODY="${PROFILES}" refused_at "13/15" 2 13.Configurations/15.configurations_profiles_id_GET.sh
ST_GET=401 GET_BODY="${B_401}" run 13.Configurations/15.configurations_profiles_id_GET.sh p1
expect "13/15: a refused read of a given id is exit 1, with its status, after one call" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'HTTP 401')" "1:1:1"
GET_BODY="${B_ARRAY}" run 17.AccessPolicies/04.accessPolicies_id_GET.sh
expect "17/04: with no id and none of our rules in the list, it is exit 1 after the one call" "${RC}:$(ncalls)" "1:1"
has "17/04: and says there is none when the list holds none of ours" "There is no rule for example_user on example_db."

echo
echo "=== 16.TransferLogs/02: one call a day ==="
COUNT7=$(body count7 '{"resultSet":{"returnCount":1,"totalCount":7},"result":[{"id":"x"}]}')
GET_BODY="${COUNT7}" run 16.TransferLogs/02.logs_transfers_GET_billable.sh 3 john
expect "billable: three days, each 7, total 21, exit 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '  7$'):$(printf '%s\n' "${OUT}" | grep -c 'Total: 21 billable transfer(s) in 3 day(s)')" "0:3:1"
ST_GET=401 GET_BODY="${B_401}" run 16.TransferLogs/02.logs_transfers_GET_billable.sh 3
expect "billable: a refused day is exit 1 after one call, with its status and no total" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'HTTP 401'):$(printf '%s\n' "${OUT}" | grep -c 'Total')" "1:1:1:0"
ST_GET_SEQ="200 500" GET_BODY="${B_500}" run 16.TransferLogs/02.logs_transfers_GET_billable.sh 3
expect "billable: a day that fails in the middle stops there, with no total that would be too small" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'Total')" "1:2:0"
NO_COUNT=$(body nocount '{"result":[]}')
GET_BODY="${NO_COUNT}" run 16.TransferLogs/02.logs_transfers_GET_billable.sh 2
expect "billable: a 200 with no count is said, every day is tried, and the exit code is 1" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'could not read a count'):$(printf '%s\n' "${OUT}" | grep -c 'Total: 0')" "1:2:2:1"

echo
echo "=== 18.AccountSetup: no password anyone could guess ==="
SETUP_OK=$(body setup_ok '{"messages":[{"message":"Account with name example_setup created.","url":"x"}]}')
for S in 01.accountSetup_POST.sh 03.accountSetup_POST_existing.sh; do
    ST_POST=200 POST_BODY="${SETUP_OK}" ACCOUNT_PASSWORD='my "own" p@ss' run "18.AccountSetup/${S}"
    expect "${S}: a password given is the one sent, in the account and in the site" "$(payload 1 | jq -c '.accountSetup | [.account.user.passwordCredentials.password, .sites[0].password]')" '["my \"own\" p@ss","my \"own\" p@ss"]'
    expect "${S}: and it is not printed" "$(printf '%s\n' "${OUT}" | grep -c 'my "own" p@ss')" "0"
    ST_POST=200 POST_BODY="${SETUP_OK}" ACCOUNT_PASSWORD= run "18.AccountSetup/${S}"
    SENT=$(payload 1 | jq -r '.accountSetup.sites[0].password')
    expect "${S}: with none given, 12 random letters and digits follow a fixed beginning" "$(printf '%s' "${SENT}" | grep -cE '^Ex1![A-Za-z0-9]{12}$')" "1"
    expect "${S}: the account and the site get the same one" "$(payload 1 | jq -r '.accountSetup.account.user.passwordCredentials.password')" "${SENT}"
    expect "${S}: and it is printed once, so that it can be used" "$(printf '%s\n' "${OUT}" | grep -cF "${SENT}")" "1"
    expect "${S}: it was not the placeholder it used to be" "$(printf '%s' "${SENT}" | grep -c 'change_me')" "0"
    ST_POST=200 POST_BODY="${SETUP_OK}" ACCOUNT_PASSWORD= run "18.AccountSetup/${S}"
    expect "${S}: a second run draws another one" "$([ "$(payload 1 | jq -r '.accountSetup.sites[0].password')" != "${SENT}" ] && echo different)" "different"
    ST_POST=400 POST_BODY="${B_500}" ACCOUNT_PASSWORD= run "18.AccountSetup/${S}"
    expect "${S}: a 400 is exit 1" "${RC}" "1"
    expect "${S}: and the generated password is printed all the same: part of it may have been created" "$(printf '%s\n' "${OUT}" | grep -cE 'generated: it is not shown again')" "1"
    expect "${S}: no script keeps the placeholder" "$(grep -c 'change_me' "${ADMIN_TREE}/18.AccountSetup/${S}" | tr -d ' '):$(grep -c 'change_me' "${BAT_TREE}/18.AccountSetup/${S%.sh}.bat" | tr -d ' ')" "0:0"
done

echo
echo "=== 20.AdministrativeRoles/05: the role is read, and its status looked at, before it is changed ==="
ROLE=$(body role '{"roleName":"example_role","isLimited":true,"menus":["Change Password"],"metadata":{"links":{}}}')
S=20.AdministrativeRoles/05.administrativeRoles_name_PUT.sh
ST_GET=200 GET_BODY="${ROLE}" ST_PUT=204 run "${S}"
expect "05 PUT: a role that is read is put back, with the menus" "${RC}:$(calls)" "0:GET ${BASE}/administrativeRoles/example_role
PUT ${BASE}/administrativeRoles/example_role"
NO_ROLE=$(body no_role '{"message":"Error validating request","validationErrors":["No such administrative role."]}')
ST_GET=404 GET_BODY="${NO_ROLE}" run "${S}"
expect "05 PUT: a role that is not there (404) is exit 1, with the way to make it, and no PUT" "${RC}:$(calls | grep -c PUT):$(printf '%s\n' "${OUT}" | grep -c 'There is no role example_role. Run 02.administrativeRoles_POST.sh first.')" "1:0:1"
ST_GET=401 GET_BODY="${B_401}" run "${S}"
expect "05 PUT: a read that is refused is exit 1, with its status, and no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
has "05 PUT: 401 is said as it is, not as a missing role" "Could not read the role example_role: HTTP 401"
ST_GET=500 GET_BODY="${B_500}" run "${S}"
expect "05 PUT: a 500 is exit 1 and no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
ST_GET=200 GET_BODY="${ROLE}" ST_PUT=400 ERR_BODY="${NO_ROLE}" run "${S}"
expect "05 PUT: a PUT that is refused is exit 1" "${RC}" "1"
ST_GET=200 GET_BODY="${NO_ROLE}" run "${S}"
expect "05 PUT: a 200 that holds no role is not put back either" "${RC}:$(calls | grep -c PUT)" "1:0"

echo
echo "=== 09.CompositeRoutes/02: three routes, each created, each checked ==="
TPL=$(body tpl '{"result":[{"id":"tpl-1"}]}')
S=09.CompositeRoutes/02.routes_POST.sh
GET_BODY="${TPL}" LOC_PREFIX=route- run "${S}"
expect "02: the template is looked up, then three routes are created" "${RC}:$(calls)" "0:GET ${BASE}/routes?fields=id&name=RouteFromAccountant
POST ${BASE}/routes
POST ${BASE}/routes
POST ${BASE}/routes"
expect "02: the first route inherits the template, with no steps, the body built by jq" "$(payload 1 | jq -c .)" '{"account":"john","name":"CompositeRoute_WithoutExtension","type":"COMPOSITE","conditionType":"MATCH_ALL","routeTemplate":"tpl-1"}'
expect "02: the simple route has one EncodingConversion step" "$(payload 2 | jq -c '[.name, .type, .steps[0].type, .steps[0].usePrecedingStepFiles]')" '["SimpleRouteName","SIMPLE","EncodingConversion",false]'
expect "02: the last route runs the simple route, by the id of its Location (the second POST)" "$(payload 3 | jq -c '[.name, .routeTemplate, .steps[0].executeRoute, .steps[0].autostart]')" '["CompositeRoute_WithExtension","tpl-1","route-2",false]'
expect "02: each creation prints its status" "$(printf '%s\n' "${OUT}" | grep -c '^HTTP 201$')" "3"
has "02: and the id of the simple route" "New resource ID: route-2"
expect "02: the header file is removed" "$(ls "${WORK}/tmp" | wc -l | tr -d ' ')" "0"
ST_GET=401 GET_BODY="${B_401}" run "${S}"
expect "02: a template lookup that is refused is exit 1 after one call, nothing created" "${RC}:$(ncalls)" "1:1"
has "02: with its status" "HTTP 401"
GET_BODY="$(body no_tpl '{"result":[]}')" run "${S}"
expect "02: no template is exit 1, nothing created" "${RC}:$(ncalls)" "1:1"
GET_BODY="${TPL}" ST_POST=400 POST_BODY="${NO_ROLE}" run "${S}"
expect "02: a creation that is refused stops the script, with the reason the server gives" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'No such administrative role.')" "1:2:1"
has "02: and its status" "HTTP 400"
GET_BODY="${TPL}" ST_POST_SEQ="201 500" POST_BODY="${B_500}" LOC_PREFIX=route- run "${S}"
expect "02: the simple route refused is exit 1 and the last route is not created" "${RC}:$(ncalls)" "1:3"
GET_BODY="${TPL}" run "${S}"
expect "02: a creation with no Location is exit 1, and the last route is not created" "${RC}:$(ncalls)" "1:3"
has "02: and says so" "Could not read the Location header"

S=09.CompositeRoutes/05.routes_POST_composite_subscription.sh
FOUND=$(body found '{"result":[{"id":"obj-1","folder":"/inbox"}]}')
GET_BODY="${FOUND}" run "${S}"
expect "05: three lookups, then the creation" "${RC}:$(calls)" "0:GET ${BASE}/routes?fields=id&name=RouteFromPartner
GET ${BASE}/subscriptions?account=john
GET ${BASE}/routes?fields=id&name=SimpleRoute_Compress
POST ${BASE}/routes"
has "05: prints the status of the creation" "HTTP 201"
expect "05: the body" "$(payload 1 | jq -c '[.routeTemplate, .subscriptions, .steps[0].executeRoute]')" '["obj-1",["obj-1"],"obj-1"]'
ST_GET=401 GET_BODY="${B_401}" run "${S}"
expect "05: a lookup that is refused is exit 1 after one call, with its status" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c 'HTTP 401')" "1:1:1"
GET_BODY="$(body none '{"result":[]}')" run "${S}"
expect "05: no template is exit 1, nothing created" "${RC}:$(ncalls)" "1:1"
ST_GET_SEQ="200 200 500" GET_BODY="${FOUND}" run "${S}"
expect "05: the third lookup refused is exit 1, nothing created" "${RC}:$(ncalls)" "1:3"
GET_BODY="${FOUND}" ST_POST=409 POST_BODY="${NO_ROLE}" run "${S}"
expect "05: a creation that is refused is exit 1, with its status and the reason" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 409'):$(printf '%s\n' "${OUT}" | grep -c 'No such administrative role.')" "1:1:1"


# ==============================================================================
# The bat twins cannot run here. What can be read from their text is checked:
# the status of every call is read with %%{http_code} and compared, a refused
# call is exit 1 and a wrong argument exit 2 as in bash, nothing is printed
# straight from curl, every CALL and GOTO has its label, no line has a quote
# that is not closed, and the exit codes are written in the header as in bash.
# ==============================================================================
echo
echo "=== The bat twins (their text) ==="
python3 - "${ADMIN_TREE}" "${BAT_TREE}" <<'PYEOF'
import os, re, sys
bash_tree, bat_tree = sys.argv[1], sys.argv[2]
SCRIPTS = """
01.Authentication/01.myself_POST 01.Authentication/01.myself_cookie_POST
02.Introduction/01.version_GET 02.Introduction/02.version_GET 02.Introduction/03.myself_GET 02.Introduction/05.myself_POST 02.Introduction/06.myself_DELETE
03.Connect/01.daemons_GET 03.Connect/02.daemons_name_GET 03.Connect/06.servers_GET 03.Connect/08.servers_name_HEAD 03.Connect/09.servers_name_GET
04.Applications/01.applications_GET 05.Accounts/01.accounts_GET 06.TransferSites/03.sites_GET 07.Subscriptions/01.subscriptions_GET
09.CompositeRoutes/02.routes_POST 09.CompositeRoutes/05.routes_POST_composite_subscription 09.CompositeRoutes/06.routes_GET
11.Certificates/01.certificates_GET 11.Certificates/10.certificates_requests_GET 12.BusinessUnits/02.businessUnits_GET
13.Configurations/03.configurations_options_GET 13.Configurations/07.configurations_options_groups_GET 13.Configurations/09.configurations_logging_GET
13.Configurations/13.configurations_profiles_GET 13.Configurations/37.configurations_externalStores_GET
16.TransferLogs/01.logs_transfers_GET 16.TransferLogs/02.logs_transfers_GET_billable 17.AccessPolicies/01.accessPolicies_GET
18.AccountSetup/01.accountSetup_POST 18.AccountSetup/03.accountSetup_POST_existing 19.AddressBook/01.addressBook_sources_GET
20.AdministrativeRoles/01.administrativeRoles_GET 20.AdministrativeRoles/05.administrativeRoles_name_PUT 21.Administrators/01.administrators_GET
22.DeniedUsers/01.deniedUsers_GET 23.Events/01.events_GET 24.IcapServers/01.icapServers_GET 25.LdapDomains/01.ldapDomains_GET
26.LoginRestrictionPolicies/01.loginRestrictionPolicies_GET 27.AuditLogs/01.logs_audit_GET 28.ServerLogs/01.logs_server_GET
29.MailTemplates/01.mailTemplates_GET 35.TransferProfiles/01.transferProfiles_GET 36.UserClasses/01.userClasses_GET 37.Zones/01.zones_GET
06.TransferSites/06.sites_id_GET 07.Subscriptions/06.subscriptions_id_GET 11.Certificates/05.certificates_id_GET
11.Certificates/12.certificates_requests_id_GET 13.Configurations/15.configurations_profiles_id_GET 17.AccessPolicies/04.accessPolicies_id_GET
19.AddressBook/03.addressBook_sources_id_GET 35.TransferProfiles/04.transferProfiles_id_GET 36.UserClasses/04.userClasses_id_GET
""".split()
failed = False
def ok(msg): print("  PASS  " + msg)
def bad(msg):
    global failed
    failed = True
    print("  FAIL  " + msg)

# check NAME PREDICATE(bat_text, bash_text, rel) -> None or a problem text; one line for all, or one per offender
def check(name, pred, only=None):
    offenders = []
    n = 0
    for rel in SCRIPTS:
        if only and rel not in only:
            continue
        bat = open(os.path.join(bat_tree, rel + ".bat"), encoding="utf-8").read()
        sh = open(os.path.join(bash_tree, rel + ".sh"), encoding="utf-8").read()
        n += 1
        problem = pred(bat, sh, rel)
        if problem:
            offenders.append("%s: %s" % (rel, problem))
    if offenders:
        for o in offenders:
            bad("%s  (%s)" % (name, o))
    else:
        ok("%s  (%d scripts)" % (name, n))

def code(text):
    """the lines that are not comments"""
    return [l for l in text.split("\n") if not re.match(r"^\s*REM\b", l, re.I) and l.strip()]

check("reads the status with curl -w and %%{http_code}",
      lambda b, s, r: None if "%%{http_code}" in b else "no %%{http_code}")
check("never writes the single percent form %{http_code}",
      lambda b, s, r: "has %{http_code}" if re.search(r"(^|[^%])%\{http_code\}", b) else None)
check("compares the status it read",
      lambda b, s, r: None if re.search(r'"%(HTTP_CODE|RESPONSE_CODE)%"==', b) else "no comparison of the status")
check("is exit 1 on a refusal (EXIT /B 1) where bash is exit 1",
      lambda b, s, r: None if ("exit 1" not in s or re.search(r"EXIT /B 1", b)) else "no EXIT /B 1")
check("is exit 2 on a wrong argument (EXIT /B 2) where bash is exit 2",
      lambda b, s, r: None if ("exit 2" not in s or re.search(r"EXIT /B 2", b)) else "no EXIT /B 2")
check("starts with SETLOCAL, so nothing it sets stays in the console",
      lambda b, s, r: None if re.search(r"^SETLOCAL\s*$", b, re.M) else "no SETLOCAL")
check("sets no password placeholder",
      lambda b, s, r: "has change_me" if "change_me" in b or "change_me" in s else None)
# a GET printed straight from curl is a status nobody looked at: every curl is in a FOR /F that takes the code
DIRECT = {"03.Connect/08.servers_name_HEAD": "prints the headers of the HEAD on purpose"}
check("no curl prints straight to the console, or to a file by redirection",
      lambda b, s, r: None if r in DIRECT else (
          "a curl is called directly" if any(re.match(r"^\s*curl\b", l, re.I) for l in code(b)) else
          ("a redirection to a file" if re.search(r"curl.*>\s*\"?%", "\n".join(code(b))) else None)))
check("every curl that takes the status ends its FOR /F with DO SET HTTP_CODE=%%C",
      lambda b, s, r: None if r in DIRECT else (
          "a FOR /F curl line without it" if any(re.search(r"FOR /F %%C IN \('curl", l) and not re.search(r"DO SET HTTP_CODE=%%C\s*$", l) for l in code(b)) else None))
def labels(b):
    defined = set(m.group(1).lower() for m in re.finditer(r"^:([A-Za-z_][A-Za-z0-9_]*)\s*$", b, re.M))
    used = set(m.group(1).lower() for m in re.finditer(r"\b(?:CALL|GOTO)\s+:?([A-Za-z_][A-Za-z0-9_]*)", "\n".join(code(b)), re.I))
    used -= {"set_variables", "eof"}
    used = set(u for u in used if u not in ("..", ))
    return sorted(u for u in used - defined if not u.endswith(".bat"))
check("every CALL and GOTO has its label",
      lambda b, s, r: ("missing label: " + ", ".join(labels(b))) if labels(b) else None)
def odd_quotes(b):
    out = []
    for i, l in enumerate(code(b), 1):
        if l.count('"') % 2 and not l.rstrip().endswith("^"):
            out.append(l.strip()[:60])
    return out
check("no line has a double quote that is not closed",
      lambda b, s, r: ("a quote is open in: " + odd_quotes(b)[0]) if odd_quotes(b) else None)
def exit_lines(text, comment):
    # the bat says findstr where bash says grep
    return [l[len(comment):].strip().replace("greps", "findstr calls").replace("grep", "findstr")
            for l in text.split("\n") if l.startswith(comment) and "Exit codes:" in l]
check("states its exit codes in the header as bash does",
      lambda b, s, r: None if exit_lines(b, "REM ") == exit_lines(s, "# ") and exit_lines(s, "# ") else "the header's exit codes differ")
check("ends every path with EXIT /B (the exit code is the call's, not the last command's)",
      lambda b, s, r: None if re.search(r"^EXIT /B", "\n".join(code(b)), re.M) else "no EXIT /B")
check("a script with a subroutine for the read calls it",
      lambda b, s, r: None if ":st_get" not in b or "CALL :st_get" in b else ":st_get is never called")
check("a script that logs the generated password says it is generated",
      lambda b, s, r: None if "Ex1!" not in b or "generated: it is not shown again" in b else "does not print it",
      only=["18.AccountSetup/01.accountSetup_POST", "18.AccountSetup/03.accountSetup_POST_existing"])
check("a DELETE logs out with the jar and the csrfToken of the login",
      lambda b, s, r: None if ("cookie.jar" in b and "csrfToken" in b) else "no jar or token",
      only=["02.Introduction/06.myself_DELETE", "01.Authentication/01.myself_cookie_POST"])
check("the login of 01.myself_POST is a POST",
      lambda b, s, r: None if "-X POST" in b and "-X GET" not in b else "not a POST",
      only=["01.Authentication/01.myself_POST"])
sys.exit(1 if failed else 0)
PYEOF
if [ $? -ne 0 ]; then FAILED=1; fi

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_sweep_c: PASS"
else
    echo "test_bash_admin_sweep_c: FAIL"
fi
exit "${FAILED}"
