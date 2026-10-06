#!/bin/bash
# ==============================================================================
# Run the Admin API examples added from the API reference against a stub curl,
# and check the calls they make: the method, the URL with its query, the body,
# the answers they act on, and their exit codes.
#
# One section per resource, in the order of the API reference. The stub answers
# different URLs differently (STUB_CURL_GET_RULES), or a sequence of answers
# (STUB_CURL_GET_SEQUENCE), for an example that lists, acts and lists again.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
ADMIN_TREE="${REPO}/Admin/API 2.0/bash"

WORK="${TESTS_DIR}/output/bash_admin_api"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin" "${WORK}/files"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/admin/set_variables.sh"
BASE="https://st.example.com:8444/api/v2.0"

# body NAME JSON: a canned answer, in a file
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
# sequence NAME JSON...: a folder of answers, served one per GET
sequence() {
    local dir="${WORK}/seq_$1" i=0
    shift
    rm -rf "${dir}" && mkdir -p "${dir}"
    for answer in "$@"; do i=$((i + 1)); printf '%s\n' "${answer}" > "${dir}/${i}.json"; done
    echo "${dir}"
}
# run FOLDER/SCRIPT ARGS...: GET_BODY, SEQUENCE, POST_BODY, LOCATION, STATUS and
# STATUS_GET set the answers
run() {
    local rel="$1"; shift
    mkdir -p "${WORK}/admin/$(dirname "${rel}")"
    cp "${ADMIN_TREE}/${rel}" "${WORK}/admin/${rel}"
    OUT=$(cd "${WORK}/admin/$(dirname "${rel}")" && PATH="${WORK}/bin:${PATH}" \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_SEQUENCE="${SEQUENCE:-}" \
          STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_LOCATION_ID="${LOCATION:-}" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE=1 \
          bash "./$(basename "${rel}")" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }

echo "=== 17.AccessPolicies ==="
F=17.AccessPolicies
SERVER_RULES='[{"id":1,"connectionType":"local","database":"all","user":"all","address":null,"authMethod":"scram-sha-256"}]'
WITH_ONE='[{"id":1,"connectionType":"local","database":"all","user":"all","address":null,"authMethod":"scram-sha-256"},{"id":2,"connectionType":"host","database":"example_db","user":"example_user","address":"samehost","authMethod":"reject"}]'
WITH_TWO='[{"id":1,"connectionType":"local","database":"all","user":"all","address":null,"authMethod":"scram-sha-256"},{"id":2,"connectionType":"host","database":"example_db","user":"example_user","address":"samehost","authMethod":"reject"},{"id":3,"connectionType":"host","database":"example_db","user":"example_user","address":"samehost","authMethod":"reject"}]'

GET_BODY=$(body rules_one "${WITH_ONE}")
run "${F}/01.accessPolicies_GET.sh"
expect "01 GET: every rule, then some fields only" "$(calls)" "GET ${BASE}/accessPolicies
GET ${BASE}/accessPolicies?fields=id,connectionType,database,user,address,authMethod"
has "01 GET: one line per rule, - for no address" "  1  local  all  all  -  scram-sha-256"

STATUS=201 LOCATION=4 run "${F}/02.accessPolicies_POST.sh"
expect "02 POST: POST /accessPolicies" "${RC}:$(calls)" "0:POST ${BASE}/accessPolicies"
expect "02 POST: a reject rule for example_user on example_db, from samehost" \
  "$(payload 1 | jq -c '[.connectionType, .database, .user, .address, .authMethod]')" \
  '["host","example_db","example_user","samehost","reject"]'
has "02 POST: prints the new rule's id from Location" "The new rule is number 4."

run "${F}/03.accessPolicies_id_HEAD.sh"
expect "03 HEAD: looks the rule up, then HEADs its id" "${RC}:$(calls)" "0:GET ${BASE}/accessPolicies
HEAD ${BASE}/accessPolicies/2"
run "${F}/03.accessPolicies_id_HEAD.sh" 7
expect "03 HEAD: an id given is used as it is" "$(calls)" "HEAD ${BASE}/accessPolicies/7"
STATUS=404 run "${F}/03.accessPolicies_id_HEAD.sh" 7
expect "03 HEAD: 404 is 'does not exist', exit 1" "${RC}" "1"

run "${F}/04.accessPolicies_id_GET.sh"
expect "04 GET id: the rule, then some fields of it" "$(calls)" "GET ${BASE}/accessPolicies
GET ${BASE}/accessPolicies/2
GET ${BASE}/accessPolicies/2?fields=database,user,authMethod"

STATUS=204 run "${F}/05.accessPolicies_id_PUT.sh" md5
expect "05 PUT: on the rule looked up" "$(calls)" "GET ${BASE}/accessPolicies
PUT ${BASE}/accessPolicies/2"
expect "05 PUT: sends the whole rule back, with only authMethod changed" "$(payload 1 | jq -c .)" \
  '{"id":2,"connectionType":"host","database":"example_db","user":"example_user","address":"samehost","authMethod":"md5"}'

GET_BODY=$(body rules_none "${SERVER_RULES}")
run "${F}/05.accessPolicies_id_PUT.sh"
expect "05 PUT: no rule to change, exit 1, nothing sent" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY=

# Two matching rules: after each delete the list is read again, and shows the ids moved
SEQUENCE=$(sequence delete "${WITH_TWO}" "${WITH_ONE}" "${SERVER_RULES}")
STATUS=204 run "${F}/06.accessPolicies_id_DELETE.sh"
expect "06 DELETE: lists again before each delete, last match first, until none is left" "${RC}:$(calls)" "0:GET ${BASE}/accessPolicies
DELETE ${BASE}/accessPolicies/3
GET ${BASE}/accessPolicies
DELETE ${BASE}/accessPolicies/2
GET ${BASE}/accessPolicies"
expect "06 DELETE: never touches the server's own rule" "$(calls | grep -c 'accessPolicies/1$')" "0"
SEQUENCE=$(sequence delete_fail "${WITH_ONE}")
STATUS=404 run "${F}/06.accessPolicies_id_DELETE.sh"
expect "06 DELETE: a refused delete stops it, exit 1" "${RC}:$(calls | grep -c DELETE)" "1:1"
SEQUENCE=

echo
echo "=== 18.AccountSetup ==="
F=18.AccountSetup
POST_BODY=$(body setup_ok '{"messages":[{"message":"Account with name example_setup created.","url":"x"},{"message":"Site with name example_setup_site created.","url":"y"}],"certificates":[]}')
ACCOUNT_PASSWORD='p@ss w0rd' run "${F}/01.accountSetup_POST.sh"
expect "01 POST: one call to /accountSetup" "${RC}:$(calls)" "0:POST ${BASE}/accountSetup"
expect "01 POST: the account, and its site, which names the account too" \
  "$(payload 1 | jq -c '.accountSetup | [.account.name, .account.user.passwordCredentials.password, .sites[0].name, .sites[0].account, .sites[0].usePassword]')" \
  '["example_setup","p@ss w0rd","example_setup_site","example_setup",true]'
has "01 POST: prints one line per message" "  Site with name example_setup_site created."
STATUS=400 run "${F}/01.accountSetup_POST.sh"
expect "01 POST: a 400 is a failure, and it says part may exist" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Part of it may have been created')" "1:1"

POST_BODY=$(body setup_existing '{"messages":[{"message":"Account with name example_setup skipped because it already exists.","url":"x"},{"message":"Site with name example_setup_site2 created.","url":"y"}]}')
run "${F}/03.accountSetup_POST_existing.sh"
expect "03 POST existing: the same account, and only the new site" \
  "$(payload 1 | jq -c '.accountSetup | [.account.name, [.sites[].name], .sites[0].downloadFolder]')" '["example_setup",["example_setup_site2"],"/in"]'
has "03 POST existing: prints the skip" "skipped because it already exists"
POST_BODY=

GET_BODY=$(body setup_get '{"accountSetup":{"account":{"name":"example_setup","type":"user","homeFolder":"/home/example_setup"},"certificates":{"login":[],"partner":[{"id":"c"}],"private":[]},"sites":[{"name":"s1"},{"name":"s2"}],"transferProfiles":[],"routes":[],"subscriptions":[{"folder":"/in"}]}}')
run "${F}/02.accountSetup_name_GET.sh"
expect "02 GET: /accountSetup/{name}, example_setup by default" "${RC}:$(calls)" "0:GET ${BASE}/accountSetup/example_setup"
has "02 GET: counts the certificates of every kind" "  certificates       1"
has "02 GET: lists the sites" "  sites              s1, s2"
run "${F}/02.accountSetup_name_GET.sh" other
expect "02 GET: takes another account" "$(calls)" "GET ${BASE}/accountSetup/other"
GET_BODY=

STATUS=204 run "${F}/04.accounts_name_DELETE.sh"
expect "04 DELETE: the account, which takes its sites and profiles with it" "${RC}:$(calls)" "0:DELETE ${BASE}/accounts/example_setup"

echo
echo "=== 19.AddressBook ==="
F=19.AddressBook
U="${BASE}/addressBook/sources"
GET_BODY=$(body sources '{"resultSet":{"returnCount":1},"result":[{"id":"src-1","name":"LDAP","type":"LDAP","parentGroup":"LDAP","enabled":true,"customProperties":{"MaxPageEntries":"100","ldapDomainName":"d"}}]}')
run "${F}/01.addressBook_sources_GET.sh"
expect "01 GET: all, the LDAP ones, the enabled ones' fields" "$(calls)" "GET ${U}
GET ${U}?type=LDAP
GET ${U}?enabled=true&fields=id,type,name,parentGroup"
has "01 GET: one line per source" "  src-1  LDAP  LDAP  LDAP"

run "${F}/02.addressBook_sources_id_HEAD.sh"
expect "02 HEAD: looks the id up by name, then HEADs it" "${RC}:$(calls)" "0:GET ${U}?name=LDAP&fields=id
HEAD ${U}/src-1"
run "${F}/02.addressBook_sources_id_HEAD.sh" Local
expect "02 HEAD: takes another source's name" "$(calls | head -n 1)" "GET ${U}?name=Local&fields=id"

run "${F}/03.addressBook_sources_id_GET.sh"
expect "03 GET id: the source, then its custom properties" "$(calls | tail -n 2)" "GET ${U}/src-1
GET ${U}/src-1?fields=customProperties"

STATUS=204 run "${F}/04.addressBook_sources_id_PUT.sh" 50
expect "04 PUT: on the source looked up" "${RC}:$(calls | tail -n 1)" "0:PUT ${U}/src-1"
expect "04 PUT: the whole source back, MaxPageEntries changed, as a string" "$(payload 1 | jq -c '[.id, .name, .enabled, .customProperties]')" \
  '["src-1","LDAP",true,{"MaxPageEntries":"50","ldapDomainName":"d"}]'
has "04 PUT: prints the value before, to put back" "MaxPageEntries of LDAP is now 100."
run "${F}/04.addressBook_sources_id_PUT.sh"
expect "04 PUT: needs a number, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

STATUS=204 run "${F}/05.addressBook_sources_id_PATCH.sh" 50
expect "05 PATCH: replaces the property that is there" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/customProperties/MaxPageEntries","value":"50"}]'
GET_BODY=$(body sources_unset '{"result":[{"id":"src-2","name":"Local","type":"LOCAL","customProperties":{"buType":"allBU"}}]}')
STATUS=204 run "${F}/05.addressBook_sources_id_PATCH.sh" 50 Local
expect "05 PATCH: adds the property that is not there" "$(payload 1 | jq -r '.[0].op')" "add"
GET_BODY=$(body sources_none '{"result":[]}')
run "${F}/05.addressBook_sources_id_PATCH.sh" 50 Nope
expect "05 PATCH: no such source, exit 1, nothing sent" "${RC}:$(calls | grep -c PATCH)" "1:0"
GET_BODY=

echo
echo "=== 20.AdministrativeRoles ==="
F=20.AdministrativeRoles
U="${BASE}/administrativeRoles"
ROLE_JSON='{"roleName":"example_role","roleType":"LIMITED","isLimited":true,"isBounceAllowed":false,"menus":["Change Password"],"metadata":{"links":{"members":"https://st.example.com:8444/api/v2.0/administrators?roleName=example_role&fields=loginName"}}}'
GET_BODY=$(body roles '{"result":[{"roleName":"example_role","menus":["Change Password","Audit Log"]}]}')
run "${F}/01.administrativeRoles_GET.sh"
expect "01 GET: a page, then the limited ones' names and menus" "$(calls)" "GET ${U}?limit=5&offset=0
GET ${U}?isLimited=true&fields=roleName,menus"
has "01 GET: one line per role, its menus joined" "  example_role: Change Password, Audit Log"
GET_BODY=

run "${F}/02.administrativeRoles_POST.sh"
expect "02 POST: POST /administrativeRoles" "$(calls)" "POST ${U}"
expect "02 POST: a limited example_role that opens Change Password" \
  "$(payload 1 | jq -c '[.roleName, .isLimited, .menus]')" '["example_role",true,["Change Password"]]'

run "${F}/03.administrativeRoles_name_HEAD.sh" "Master Administrator"
expect "03 HEAD: the name, its space encoded" "${RC}:$(calls)" "0:HEAD ${U}/Master%20Administrator"
STATUS=404 run "${F}/03.administrativeRoles_name_HEAD.sh"
expect "03 HEAD: 404 is 'does not exist', exit 1" "${RC}:$(calls)" "1:HEAD ${U}/example_role"

SEQUENCE=$(sequence role_get "${ROLE_JSON}" '{"result":[{"loginName":"example_admin"}]}')
run "${F}/04.administrativeRoles_name_GET.sh"
expect "04 GET: the role, then its members link" "${RC}:$(calls)" "0:GET ${U}/example_role
GET ${BASE}/administrators?roleName=example_role&fields=loginName"
has "04 GET: lists the administrators that hold it" "  example_admin"
SEQUENCE=
STATUS_GET=404 GET_BODY=$(body role_missing '{"message":"not found"}') run "${F}/04.administrativeRoles_name_GET.sh"
expect "04 GET: a 404 exits 1, no members call" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"

GET_BODY=$(body role "${ROLE_JSON}")
STATUS=204 run "${F}/05.administrativeRoles_name_PUT.sh"
expect "05 PUT: read, then PUT the role" "${RC}:$(calls)" "0:GET ${U}/example_role
PUT ${U}/example_role"
expect "05 PUT: the whole role, default menus, no metadata" \
  "$(payload 1 | jq -c '[.roleName, .isLimited, .menus, has("metadata")]')" '["example_role",true,["Change Password","Audit Log"],false]'
STATUS=204 run "${F}/05.administrativeRoles_name_PUT.sh" "File Tracking" "Change Password"
expect "05 PUT: the menus given, one argument each" "$(payload 1 | jq -c .menus)" '["File Tracking","Change Password"]'
GET_BODY=$(body role_none '{"message":"not found"}')
run "${F}/05.administrativeRoles_name_PUT.sh"
expect "05 PUT: no such role, exit 1, nothing sent" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY=

STATUS=204 run "${F}/06.administrativeRoles_name_PATCH.sh"
expect "06 PATCH: PATCH the role" "${RC}:$(calls)" "0:PATCH ${U}/example_role"
expect "06 PATCH: appends a menu with /menus/-" "$(payload 1 | jq -c .)" '[{"op":"add","path":"/menus/-","value":"File Tracking"}]'

STATUS=204 run "${F}/07.administrativeRoles_name_DELETE.sh"
expect "07 DELETE: the role" "${RC}:$(calls)" "0:DELETE ${U}/example_role"
STATUS=204 run "${F}/07.administrativeRoles_name_DELETE.sh" "Delegated Administrator"
expect "07 DELETE: moves the members to the target role, the name URL-encoded by curl" "$(calls)" "DELETE ${U}/example_role?targetRoleName=Delegated Administrator"
STATUS=409 run "${F}/07.administrativeRoles_name_DELETE.sh"
expect "07 DELETE: anything but 204 exits 1" "${RC}" "1"

echo
echo "=== 21.Administrators ==="
F=21.Administrators
U="${BASE}/administrators"
ADMIN_JSON='{"loginName":"example_admin","roleName":"example_role","parent":"apiadmin","locked":true,"administratorRights":{"canReadOnly":true,"isMaker":false},"passwordCredentials":{"password":"","lastLoginTime":null},"apiKeys":[{"id":"k1"}],"metadata":{"links":{}}}'
GET_BODY=$(body admins '{"result":[{"loginName":"example_admin","parent":"apiadmin","locked":true}]}')
run "${F}/01.administrators_GET.sh" example_role
expect "01 GET: a page, the role's holders, the locked ones" "$(calls)" "GET ${U}?limit=5&offset=0&fields=loginName,roleName
GET ${U}?roleName=example_role&fields=loginName,parent,locked
GET ${U}?locked=true&fields=loginName"
has "01 GET: one line each, with its parent and LOCKED" "  example_admin  created by apiadmin  LOCKED"
GET_BODY=

STATUS=201 ADMIN_PASSWORD=Synthetic-1 run "${F}/02.administrators_POST.sh"
expect "02 POST: POST /administrators" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: example_admin, example_role, parent ST_USER, local password from ADMIN_PASSWORD" \
  "$(payload 1 | jq -c '[.loginName, .roleName, .parent, .localAuthentication, .passwordCredentials.password]')" \
  '["example_admin","example_role","apiadmin",true,"Synthetic-1"]'
STATUS=400 run "${F}/02.administrators_POST.sh"
expect "02 POST: anything but 201 exits 1" "${RC}" "1"

run "${F}/03.administrators_name_HEAD.sh"
expect "03 HEAD: example_admin by default" "${RC}:$(calls)" "0:HEAD ${U}/example_admin"
STATUS=404 run "${F}/03.administrators_name_HEAD.sh" other
expect "03 HEAD: 404 is 'does not exist', exit 1" "${RC}:$(calls)" "1:HEAD ${U}/other"

GET_BODY=$(body admin "${ADMIN_JSON}")
run "${F}/04.administrators_name_GET.sh"
expect "04 GET: the administrator" "${RC}:$(calls)" "0:GET ${U}/example_admin"
has "04 GET: the summary line" "  example_admin, role example_role, created by apiadmin, LOCKED"
has "04 GET: only the rights it has" "  rights: canReadOnly"
has "04 GET: never logged in, one key" "  last login never, API keys 1"

STATUS=204 run "${F}/05.administrators_name_PUT.sh"
expect "05 PUT: read, then PUT" "${RC}:$(calls)" "0:GET ${U}/example_admin
PUT ${U}/example_admin"
expect "05 PUT: unlocked, without metadata and the API keys" \
  "$(payload 1 | jq -c '[.loginName, .locked, has("metadata"), has("apiKeys")]')" '["example_admin",false,false,false]'
GET_BODY=$(body admin_none '{"message":"not found"}')
run "${F}/05.administrators_name_PUT.sh"
expect "05 PUT: no such administrator, exit 1, nothing sent" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY=

STATUS=204 run "${F}/06.administrators_name_PATCH.sh"
expect "06 PATCH: PATCH the administrator" "${RC}:$(calls)" "0:PATCH ${U}/example_admin"
expect "06 PATCH: replaces /locked with true" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/locked","value":true}]'
run "${F}/06.administrators_name_PATCH.sh" apiadmin
expect "06 PATCH: never locks the administrator it logs in as" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

STATUS=204 run "${F}/07.administrators_name_DELETE.sh"
expect "07 DELETE: example_admin" "${RC}:$(calls)" "0:DELETE ${U}/example_admin"

POST_BODY=$(body key '{"id":"k1","key":"synthetic-key-value","expiresAt":"Thu, 08 Oct 2026 10:00:00 +0300","permissions":["read","write"]}')
STATUS=201 run "${F}/08.administrators_name_apiKeys_POST.sh" 7 read,write
expect "08 POST: POST .../api-keys" "${RC}:$(calls)" "0:POST ${U}/example_admin/api-keys"
expect "08 POST: validityDays as a number, the permissions as a list" "$(payload 1 | jq -c .)" '{"validityDays":7,"permissions":["read","write"]}'
has "08 POST: the key's id and expiry" "Key id k1, valid until Thu, 08 Oct 2026 10:00:00 +0300, permissions read, write"
has "08 POST: the key itself, shown once" "The key, shown this once: synthetic-key-value"
run "${F}/08.administrators_name_apiKeys_POST.sh" soon
expect "08 POST: DAYS must be a number, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
STATUS=409 run "${F}/08.administrators_name_apiKeys_POST.sh"
expect "08 POST: a third key (409) exits 1" "${RC}" "1"
POST_BODY=

KEYS='[{"id":"k1","expiresAt":"Thu, 08 Oct 2026 10:00:00 +0300","permissions":["read"],"lastAccessedAt":null,"expired":false},{"id":"k2","expiresAt":"Mon, 05 Oct 2026 10:00:00 +0300","permissions":["read","delete"],"lastAccessedAt":"Sun, 04 Oct 2026 10:00:00 +0300","expired":true}]'
GET_BODY=$(body keys "${KEYS}")
run "${F}/09.administrators_name_apiKeys_GET.sh"
expect "09 GET: the keys only, without KEY" "${RC}:$(calls)" "0:GET ${U}/example_admin/api-keys"
has "09 GET: one line per key, never used" "  k1  Thu, 08 Oct 2026 10:00:00 +0300  read  never"
has "09 GET: an expired key says so" "  k2  Mon, 05 Oct 2026 10:00:00 +0300  read,delete  Sun, 04 Oct 2026 10:00:00 +0300  EXPIRED"
SEQUENCE=$(sequence keys_then_me "${KEYS}" '{"loginName":"example_admin","roleName":"example_role"}')
run "${F}/09.administrators_name_apiKeys_GET.sh" synthetic-key-value
expect "09 GET: with KEY, calls /myself too" "${RC}:$(calls)" "0:GET ${U}/example_admin/api-keys
GET ${BASE}/myself"
has "09 GET: /myself with the key header" "HEADER: SECURETRANSPORT-API-KEY: synthetic-key-value"
expect "09 GET: and without -u: basic auth on the list only" "$(printf '%s\n' "${OUT}" | grep -c '^BASIC_AUTH:')" "1"
has "09 GET: who the key logs in as" "  example_admin, role example_role"
SEQUENCE=
STATUS_GET=401 run "${F}/09.administrators_name_apiKeys_GET.sh" revoked-key
expect "09 GET: a refused key exits 1" "${RC}" "1"
has "09 GET: and says so" "The key was refused (HTTP 401)"

STATUS=204 run "${F}/10.administrators_name_apiKeys_keyId_DELETE.sh"
expect "10 DELETE: every key of example_admin" "${RC}:$(calls)" "0:GET ${U}/example_admin/api-keys
DELETE ${U}/example_admin/api-keys/k1
DELETE ${U}/example_admin/api-keys/k2"
STATUS=204 run "${F}/10.administrators_name_apiKeys_keyId_DELETE.sh" k9
expect "10 DELETE: only the key given" "$(calls)" "DELETE ${U}/example_admin/api-keys/k9"
GET_BODY=$(body no_keys '[]')
run "${F}/10.administrators_name_apiKeys_keyId_DELETE.sh"
expect "10 DELETE: no keys, nothing deleted, exit 0" "${RC}:$(calls | grep -c DELETE)" "0:0"
STATUS=404 run "${F}/10.administrators_name_apiKeys_keyId_DELETE.sh" k9
expect "10 DELETE: anything but 204 exits 1" "${RC}" "1"
GET_BODY=

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_api: PASS"
else
    echo "test_bash_admin_api: FAIL"
fi
exit "${FAILED}"
