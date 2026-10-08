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
has_header() { printf '%s\n' "${OUT}" | grep -cF -- "HEADER: $1"; }
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
expect "04 GET: the role, then the administrators with roleName=" "${RC}:$(calls)" "0:GET ${U}/example_role
GET ${BASE}/administrators?roleName=example_role&fields=loginName"
has "04 GET: lists the administrators that hold it" "  example_admin"
# The server's own members link is broken for a name with a space
# (roleName=Master%2BAdministrator finds nobody): search by the name instead
SEQUENCE=$(sequence role_get_space '{"roleName":"Master Administrator","metadata":{"links":{"members":"https://st.example.com:8444/api/v2.0/administrators?roleName=Master%2BAdministrator&fields=loginName"}}}' \
  '{"result":[{"loginName":"apiadmin"}]}')
run "${F}/04.administrativeRoles_name_GET.sh" "Master Administrator"
expect "04 GET: a name with a space, members searched by the name, not the link" "${RC}:$(calls)" "0:GET ${U}/Master%20Administrator
GET ${BASE}/administrators?roleName=Master Administrator&fields=loginName"
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
echo "=== 12.BusinessUnits ==="
F=12.BusinessUnits
U="${BASE}/businessUnits"
BU_JSON='{"name":"example bu","businessUnitHierarchy":"example bu","baseFolder":"/home/example_bu","homeFolderModifyingAllowed":false,"sharedFoldersCollaborationAllowed":null,"metadata":{"links":{"accounts":"https://st.example.com:8444/api/v2.0/accounts?businessUnit=example%2Bbu"}}}'
GET_BODY=$(body bus '{"result":[{"name":"child","businessUnitHierarchy":"example bu/child","baseFolder":"/home/example_bu/child"}]}')
run "${F}/02.businessUnits_GET.sh"
expect "02 GET: a page, then every name (*), hierarchy and base folder" "$(calls)" "GET ${U}?limit=5&offset=0
GET ${U}?name=*&fields=businessUnitHierarchy,baseFolder"
has "02 GET: one line per unit, its hierarchy" "  example bu/child  /home/example_bu/child"
run "${F}/02.businessUnits_GET.sh" "example*" "example bu"
expect "02 GET: with PARENT, the nested units too" "$(calls | tail -n 1)" "GET ${U}?parent=example bu&fields=name"
GET_BODY=

run "${F}/03.businessUnits_name_HEAD.sh"
expect "03 HEAD: Finance, which 01 creates, by default" "${RC}:$(calls)" "0:HEAD ${U}/Finance"
STATUS=404 run "${F}/03.businessUnits_name_HEAD.sh" "example bu"
expect "03 HEAD: the name URL-encoded; 404 exits 1" "${RC}:$(calls)" "1:HEAD ${U}/example%20bu"

SEQUENCE=$(sequence bu_get "${BU_JSON}" '{"resultSet":{"returnCount":1,"totalCount":3},"result":[{"name":"a"}]}')
run "${F}/04.businessUnits_name_GET.sh" "example bu"
expect "04 GET: the unit, then its accounts searched by the name, not the server's link" "${RC}:$(calls)" "0:GET ${U}/example%20bu
GET ${BASE}/accounts?businessUnit=example bu&limit=1&fields=name"
has "04 GET: the hierarchy and base folder" "  example bu, base folder /home/example_bu"
has "04 GET: the account count, from totalCount" "  accounts in it: 3"
SEQUENCE=
STATUS_GET=404 GET_BODY=$(body bu_missing '{"message":"not found"}') run "${F}/04.businessUnits_name_GET.sh" nope
expect "04 GET: a 404 exits 1, no accounts call" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"

GET_BODY=$(body bu "${BU_JSON}")
STATUS=204 run "${F}/05.businessUnits_name_PUT.sh" "example bu"
expect "05 PUT: read, then PUT" "${RC}:$(calls)" "0:GET ${U}/example%20bu
PUT ${U}/example%20bu"
expect "05 PUT: the whole unit, homeFolderModifyingAllowed true, no metadata" \
  "$(payload 1 | jq -c '[.name, .baseFolder, .homeFolderModifyingAllowed, has("metadata")]')" '["example bu","/home/example_bu",true,false]'
has "05 PUT: prints the value before" "homeFolderModifyingAllowed of example bu is now false."
STATUS=204 run "${F}/05.businessUnits_name_PUT.sh" "example bu" false
expect "05 PUT: takes false" "$(payload 1 | jq -c .homeFolderModifyingAllowed)" "false"
run "${F}/05.businessUnits_name_PUT.sh"
expect "05 PUT: needs a NAME, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
run "${F}/05.businessUnits_name_PUT.sh" "example bu" yes
expect "05 PUT: VALUE is true or false, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=$(body bu_none '{"message":"not found"}')
run "${F}/05.businessUnits_name_PUT.sh" nope
expect "05 PUT: no such unit, exit 1, nothing sent" "${RC}:$(calls | grep -c PUT)" "1:0"

GET_BODY=$(body bu "${BU_JSON}")
STATUS=204 run "${F}/06.businessUnits_name_PATCH.sh" "example bu" false
expect "06 PATCH: reads the value, then PATCH" "${RC}:$(calls)" "0:GET ${U}/example%20bu?fields=sharedFoldersCollaborationAllowed
PATCH ${U}/example%20bu"
expect "06 PATCH: replaces sharedFoldersCollaborationAllowed with a boolean" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/sharedFoldersCollaborationAllowed","value":false}]'
has "06 PATCH: prints the value before, null for a new unit" "sharedFoldersCollaborationAllowed of example bu is now null."
run "${F}/06.businessUnits_name_PATCH.sh"
expect "06 PATCH: needs a NAME, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=

STATUS=204 run "${F}/07.businessUnits_name_DELETE.sh" "example bu"
expect "07 DELETE: the unit named, URL-encoded" "${RC}:$(calls)" "0:DELETE ${U}/example%20bu"
run "${F}/07.businessUnits_name_DELETE.sh"
expect "07 DELETE: no default, needs a NAME, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

echo
echo "=== 11.Certificates ==="
F=11.Certificates
U="${BASE}/certificates"
ONE='{"result":[{"id":"c0ffee01"}]}'
GET_BODY=$(body certs '{"resultSet":{"totalCount":156},"result":[{"name":"example_cert","subject":"CN=example_cert","account":null,"expirationTime":"Thu, 05 Nov 2026 14:10:41 +0200"}]}')
run "${F}/01.certificates_GET.sh" partner 10
expect "01 GET: the total count" "$(printf '%s\n' "${OUT}" | grep -cx '156')" "1"
expect "01 GET: the count, the usage's x509 ones" "$(calls | head -n 2)" "GET ${U}?limit=1&fields=id
GET ${U}?usage=partner&type=x509&fields=name,subject,expirationTime"
WINDOW=$(calls | tail -n 1 | sed -n 's/.*expirationTime.from=\([0-9]*\)&expirationTime.to=\([0-9]*\)&.*/\1 \2/p')
read -r FROM TO <<< "${WINDOW}"
expect "01 GET: the expiry window in milliseconds, DAYS wide" "$(( FROM > 1000000000000 )):$(( TO - FROM ))" "1:864000000"
has "01 GET: one line each, - for no account" "  example_cert  -  Thu, 05 Nov 2026 14:10:41 +0200"
run "${F}/01.certificates_GET.sh" local soon
expect "01 GET: DAYS must be a number, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=

STATUS=201 LOCATION=c0ffee02 CA_PASSWORD=synthetic-ca run "${F}/02.certificates_POST_generate.sh" 30
expect "02 POST: POST /certificates" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: a local x509 example_cert, signed with the CA password" \
  "$(payload 1 | jq -c '[.name, .type, .usage, .subject, .validityPeriod, .caPassword]')" \
  '["example_cert","x509","local","CN=example_cert,O=Example",30,"synthetic-ca"]'
has "02 POST: the id, from the Location header" "The new certificate's id: c0ffee02"
run "${F}/02.certificates_POST_generate.sh"
expect "02 POST: no CA_PASSWORD, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

printf -- '-----BEGIN CERTIFICATE-----\nU1lOVEhFVElD\n-----END CERTIFICATE-----\n' > "${WORK}/files/partner.pem"
POST_BODY=$(body imported '{"id":"c0ffee03","name":"example_partner","subject":"CN=partner","expirationTime":"Thu, 05 Nov 2026 14:10:41 +0200"}')
STATUS=200 run "${F}/03.certificates_POST_import_partner.sh" example_user "${WORK}/files/partner.pem"
expect "03 POST: POST /certificates, multipart/mixed" "${RC}:$(calls):$(has_header 'Content-Type: multipart/mixed; boundary=BOUNDARY')" "0:POST ${U}:1"
expect "03 POST: the JSON part, a partner certificate for the account" \
  "$(payload 1 | tr -d '\r' | sed -n '4p' | jq -c '[.name, .type, .usage, .account]')" '["example_partner","x509","partner","example_user"]'
expect "03 POST: the file part holds the certificate, then the closing boundary" \
  "$(payload 1 | tr -d '\r' | sed -n '6p;8,10p;12p' | tr '\n' '|')" "Content-Type: application/octet-stream|-----BEGIN CERTIFICATE-----|U1lOVEhFVElD|-----END CERTIFICATE-----|--BOUNDARY--"
has "03 POST: what was imported" "Imported example_partner, id c0ffee03, subject CN=partner"
run "${F}/03.certificates_POST_import_partner.sh" example_user "${WORK}/files/missing.pem"
expect "03 POST: no such file, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
POST_BODY=

GET_BODY=$(body one_cert "${ONE}")
run "${F}/04.certificates_id_HEAD.sh"
expect "04 HEAD: looks example_cert up by name, then HEADs its id" "${RC}:$(calls)" "0:GET ${U}?name=example_cert&fields=id
HEAD ${U}/c0ffee01"
GET_BODY=$(body two_certs '{"result":[{"id":"a1"},{"id":"a2"}]}')
run "${F}/04.certificates_id_HEAD.sh" shared
expect "04 HEAD: two with the name, exit 1, nothing more" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
has "04 HEAD: and says how many" "Found 2 certificates named shared"
GET_BODY=$(body one_digits '{"result":[{"id":"12345"}]}')
run "${F}/07.certificates_id_DELETE.sh" digits
expect "07 DELETE: an id of digits only is still an id" "${RC}:$(calls | tail -n 1)" "1:DELETE ${U}/12345"

GET_BODY=$(body one_cert "${ONE}")
run "${F}/05.certificates_id_GET.sh"
expect "05 GET: the certificate, its SHA256 fingerprint, its path" "$(calls | tail -n 3)" "GET ${U}/c0ffee01
GET ${U}/c0ffee01?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint
GET ${U}/c0ffee01?includePath=true&fields=name,subject"

STATUS=204 run "${F}/06.certificates_id_PATCH.sh"
expect "06 PATCH: PATCH the certificate" "${RC}:$(calls | tail -n 1)" "0:PATCH ${U}/c0ffee01"
expect "06 PATCH: accessLevel PUBLIC and an additional attribute" "$(payload 1 | jq -c '[.[] | [.op, .path, .value]]')" \
  '[["replace","/accessLevel","PUBLIC"],["add","/additionalAttributes/userVars.owner","example"]]'
run "${F}/06.certificates_id_PATCH.sh" example_cert OPEN
expect "06 PATCH: ACCESS_LEVEL is one of three, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

STATUS=204 run "${F}/07.certificates_id_DELETE.sh"
expect "07 DELETE: example_cert by default" "${RC}:$(calls | tail -n 1)" "0:DELETE ${U}/c0ffee01"

POST_BODY=$(body exported_pem '-----BEGIN CERTIFICATE-----')
STATUS=200 run "${F}/08.certificates_id_operations_POST_export.sh"
expect "08 POST: export as pem" "${RC}:$(calls | tail -n 1)" "0:POST ${U}/c0ffee01/operations?operation=export&format=pem"
expect "08 POST: always a form, even with no password" "$(printf '%s\n' "${OUT}" | grep -c '^FORM: exportPassword=$')" "1"
expect "08 POST: written to example_cert.pem" "$(cat "${WORK}/admin/${F}/example_cert.pem")" "-----BEGIN CERTIFICATE-----"
STATUS=200 EXPORT_PASSWORD=synthetic-pw run "${F}/08.certificates_id_operations_POST_export.sh" example_cert pkcs12
expect "08 POST: pkcs12, the password in the form, to .p12" \
  "$(calls | tail -n 1 | sed 's/.*format=//'):$(printf '%s\n' "${OUT}" | grep '^FORM:'):$([ -f "${WORK}/admin/${F}/example_cert.p12" ] && echo file)" \
  "pkcs12:FORM: exportPassword=synthetic-pw:file"
run "${F}/08.certificates_id_operations_POST_export.sh" example_cert pkcs12
expect "08 POST: pkcs12 needs EXPORT_PASSWORD, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
run "${F}/08.certificates_id_operations_POST_export.sh" example_cert der
expect "08 POST: FORMAT is pem, crt or pkcs12" "${RC}" "2"
POST_BODY=
GET_BODY=

R="${U}/requests"
printf -- '--Boundary_1\r\nContent-Type: application/json\r\n\r\n{\r\n  "id" : "c0ffee10",\r\n  "subject" : "CN=example_csr,O=Example"\r\n}\r\n--Boundary_1\r\nContent-Type: application/octet-stream\r\n\r\n-----BEGIN CERTIFICATE REQUEST-----\r\nU1lOVEhFVElD\r\n-----END CERTIFICATE REQUEST-----\r\n\r\n--Boundary_1--\r\n' > "${WORK}/csr_answer.txt"
POST_BODY="${WORK}/csr_answer.txt" STATUS=201 run "${F}/09.certificates_requests_POST.sh"
expect "09 POST: POST /certificates/requests" "${RC}:$(calls)" "0:POST ${R}"
expect "09 POST: a local 2048 bit request for the example subject" "$(payload 1 | jq -c '[.subject, .usage, .keySize]')" '["CN=example_csr,O=Example","local",2048]'
has "09 POST: the id, from the JSON part" "The request's id: c0ffee10"
expect "09 POST: the CSR part alone, without carriage returns, to example_csr.req" "$(cat "${WORK}/admin/${F}/example_csr.req" | od -c | grep -c '\\r'):$(head -n 1 "${WORK}/admin/${F}/example_csr.req"):$(wc -l < "${WORK}/admin/${F}/example_csr.req" | tr -d ' ')" \
  "0:-----BEGIN CERTIFICATE REQUEST-----:3"

GET_BODY=$(body requests '{"result":[{"id":"c0ffee10","subject":"CN=example_csr,O=Example","usage":"local","account":null}]}')
run "${F}/10.certificates_requests_GET.sh" local
expect "10 GET: the requests, of one usage" "$(calls)" "GET ${R}?fields=id,subject,usage,account&usage=local"
has "10 GET: one line each" "  c0ffee10  CN=example_csr,O=Example  local  -"

run "${F}/11.certificates_requests_id_HEAD.sh"
expect "11 HEAD: looks the example request up by subject, then HEADs it" "${RC}:$(calls)" "0:GET ${R}?subject=CN=example_csr,O=Example
HEAD ${R}/c0ffee10"
run "${F}/11.certificates_requests_id_HEAD.sh" given01
expect "11 HEAD: an id given is used as it is" "$(calls)" "HEAD ${R}/given01"
GET_BODY=$(body no_requests '{"result":[]}')
run "${F}/12.certificates_requests_id_GET.sh"
expect "12 GET: no request for the subject, exit 1" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
GET_BODY=$(body requests '{"result":[{"id":"c0ffee10"}]}')
run "${F}/12.certificates_requests_id_GET.sh"
expect "12 GET: the request" "$(calls | tail -n 1)" "GET ${R}/c0ffee10"

printf -- '-----BEGIN CERTIFICATE-----\nU0lHTkVE\n-----END CERTIFICATE-----\n' > "${WORK}/files/signed.pem"
POST_BODY=$(body completed '{"id":"c0ffee11","name":"example_csr_cert","expirationTime":"Thu, 08 Oct 2026 15:06:49 +0300"}')
STATUS=200 run "${F}/13.certificates_requests_id_POST_complete.sh" "${WORK}/files/signed.pem"
expect "13 POST: the signed certificate to the request" "${RC}:$(calls | tail -n 1)" "0:POST ${R}/c0ffee10"
expect "13 POST: a form, the alias and the file" "$(printf '%s\n' "${OUT}" | grep '^FORM:' | tr '\n' '|')" \
  "FORM: alias=example_csr_cert|FORM: certificateFile=@${WORK}/files/signed.pem|"
has "13 POST: the new certificate" "The new certificate example_csr_cert, id c0ffee11"
STATUS=200 run "${F}/13.certificates_requests_id_POST_complete.sh" "${WORK}/files/signed.pem" given02
expect "13 POST: a request id given is used as it is" "$(calls)" "POST ${R}/given02"
run "${F}/13.certificates_requests_id_POST_complete.sh" "${WORK}/files/missing.pem"
expect "13 POST: no such file, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
POST_BODY=

STATUS=204 run "${F}/14.certificates_requests_id_DELETE.sh"
expect "14 DELETE: the example request" "${RC}:$(calls | tail -n 1)" "0:DELETE ${R}/c0ffee10"
STATUS=404 run "${F}/14.certificates_requests_id_DELETE.sh" gone
expect "14 DELETE: anything but 204 exits 1" "${RC}" "1"
GET_BODY=

echo
echo "=== 13.Configurations ==="
F=13.Configurations
U="${BASE}/configurations"
nothing_sent() { expect "$1" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"; }

GET_BODY=$(body opts '{"resultSet":{"totalCount":1035},"result":[{"name":"AddressBook.Enabled","values":["true"],"defaultValues":["false"]}]}')
run "${F}/03.configurations_options_GET.sh"
expect "03 GET: the count, the pattern's options, the changed ones" "$(calls)" "GET ${U}/options?limit=1&fields=name
GET ${U}/options?name=AddressBook*&fields=name,values,defaultValues
GET ${U}/options?isModified=true&limit=10&fields=name,values"
has "03 GET: name = values (default)" "  AddressBook.Enabled = true (false)"
GET_BODY=

STATUS=204 run "${F}/04.configurations_options_PUT.sh" "Some.Option=a b" "Other.Option=" "Third.Option=x=y"
expect "04 PUT: reads each option, then one PUT" "$(calls)" "GET ${U}/options/Some.Option?fields=name,values
GET ${U}/options/Other.Option?fields=name,values
GET ${U}/options/Third.Option?fields=name,values
PUT ${U}/options"
expect "04 PUT: names and values, an empty one as [\"\"], = kept in a value" "$(payload 1 | jq -c .)" \
  '[{"name":"Some.Option","values":["a b"]},{"name":"Other.Option","values":[""]},{"name":"Third.Option","values":["x=y"]}]'
STATUS=204 run "${F}/04.configurations_options_PUT.sh"
expect "04 PUT: the two address book limits by default" "$(payload 1 | jq -c '[.[] | .name + "=" + .values[0]]')" \
  '["AddressBook.Limit.DefaultDisplayEntries=10","AddressBook.Limit.MaxDisplayEntries=100"]'
run "${F}/04.configurations_options_PUT.sh" "NoEquals"
nothing_sent "04 PUT: an argument without = is refused, nothing sent"

run "${F}/05.configurations_options_name_HEAD.sh"
expect "05 HEAD: AddressBook.Enabled by default" "${RC}:$(calls)" "0:HEAD ${U}/options/AddressBook.Enabled"
STATUS=404 run "${F}/05.configurations_options_name_HEAD.sh" No.Such
expect "05 HEAD: 404 exits 1" "${RC}" "1"

GET_BODY=$(body opt '{"name":"AddressBook.Enabled","values":["true"],"defaultValues":["false"],"readOnly":false,"encrypted":true,"isLocal":false}')
run "${F}/06.configurations_options_name_GET.sh"
has "06 GET: value and default" "  AddressBook.Enabled = true, default false"
has "06 GET: what can be done with it" "  can be changed, encrypted"

GET_BODY=$(body groups '[{"name":"SMTP.Group","description":"SMTP settings"}]')
run "${F}/07.configurations_options_groups_GET.sh"
expect "07 GET: the groups, a plain array" "$(calls):$(printf '%s\n' "${OUT}" | grep -c '^  SMTP.Group: SMTP settings$')" "GET ${U}/options/groups:1"
GET_BODY=$(body group '{"uiSchema":{"title":"StorageProfiles.S3.Group","description":"S3","properties":{"StorageProfiles.S3.Registry":{"type":"array","title":"Registry"}}}}')
run "${F}/08.configurations_options_groups_name_GET.sh"
expect "08 GET: the S3 storage profile group by default" "$(calls)" "GET ${U}/options/groups/StorageProfiles.S3.Group"
has "08 GET: one line per option" "  StorageProfiles.S3.Registry  array  Registry"

LOGGING='{"result":[{"name":"Logging.Admin.config","profileId":-645867027,"propagationStatus":"NONE"}]}'
GET_BODY=$(body logging "${LOGGING}")
run "${F}/09.configurations_logging_GET.sh"
has "09 GET: name, profile, status" "  Logging.Admin.config  -645867027  NONE"
run "${F}/10.configurations_logging_name_HEAD.sh"
expect "10 HEAD: looks the profile up, then HEADs with profileId" "${RC}:$(calls)" "0:GET ${U}/logging
HEAD ${U}/logging/Logging.Admin.config?profileId=-645867027"
run "${F}/10.configurations_logging_name_HEAD.sh" Logging.Ssh.config 5
expect "10 HEAD: a profile given is used as it is" "$(calls)" "HEAD ${U}/logging/Logging.Ssh.config?profileId=5"
run "${F}/10.configurations_logging_name_HEAD.sh" No.Such.config
expect "10 HEAD: an option not in the list, exit 1" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
run "${F}/11.configurations_logging_name_GET.sh" Logging.Admin.config 7
expect "11 GET: the JSON, then the XML" "$(calls)" "GET ${U}/logging/Logging.Admin.config?profileId=7
GET ${U}/logging/Logging.Admin.config?profileId=7"
expect "11 GET: the XML asked for as application/xml" "$(has_header 'accept: application/xml')" "1"
expect "11 GET: written to NAME.xml" "$([ -f "${WORK}/admin/${F}/Logging.Admin.config.xml" ] && echo file)" "file"
printf '<Configuration/>\n' > "${WORK}/files/log4j.xml"
STATUS=204 run "${F}/12.configurations_logging_name_PUT.sh" "${WORK}/files/log4j.xml" Logging.Admin.config 7
expect "12 PUT: the file as a form, to the option and profile" "${RC}:$(calls):$(printf '%s\n' "${OUT}" | grep '^FORM:')" \
  "0:PUT ${U}/logging/Logging.Admin.config?profileId=7:FORM: file=@${WORK}/files/log4j.xml;type=application/xml"
STATUS=400 run "${F}/12.configurations_logging_name_PUT.sh" "${WORK}/files/log4j.xml" Logging.Admin.config 7
expect "12 PUT: a refusal exits 1" "${RC}" "1"
run "${F}/12.configurations_logging_name_PUT.sh" "${WORK}/files/missing.xml"
nothing_sent "12 PUT: no such file, nothing sent"
GET_BODY=

PROFILES='{"result":[{"id":-1594316066,"name":"Default","protocol":null,"active":null},{"id":-645867027,"name":"SecureTransport Server Configuration","protocol":null,"active":null},{"id":1572115975,"name":"Ftp Default","protocol":"FTP","active":true}]}'
GET_BODY=$(body profiles "${PROFILES}")
run "${F}/13.configurations_profiles_GET.sh"
has "13 GET: one line per profile" "  1572115975  Ftp Default  FTP  true"
run "${F}/14.configurations_profiles_id_HEAD.sh"
expect "14 HEAD: the server's own profile by default, a negative id" "${RC}:$(calls | tail -n 1)" "0:HEAD ${U}/profiles/-645867027"
run "${F}/15.configurations_profiles_id_GET.sh" 1572115975
expect "15 GET: a profile given" "$(calls)" "GET ${U}/profiles/1572115975"
GET_BODY=

DB='{"databaseType":"PostgreSQL","host":"127.0.0.1","port":"54321","databaseName":"st","username":"stdbuser","isInternalDB":true,"databaseRunning":true,"secureConnectionEnabled":true}'
GET_BODY=$(body db "${DB}")
run "${F}/16.configurations_database_GET.sh"
has "16 GET: type, address, database, user" "  PostgreSQL (embedded) at 127.0.0.1:54321, database st, user stdbuser"
STATUS=204 DB_PASSWORD=synthetic-db run "${F}/17.configurations_database_operations_POST_test.sh"
expect "17 POST: reads the settings, then tests" "${RC}:$(calls)" "0:GET ${U}/database
POST ${U}/database/operations?operation=test"
expect "17 POST: a form with the settings and the password" "$(printf '%s\n' "${OUT}" | grep '^FORM:' | tr '\n' '|')" \
  "FORM: databaseType=PostgreSQL|FORM: host=127.0.0.1|FORM: port=54321|FORM: databaseName=st|FORM: username=stdbuser|FORM: password=synthetic-db|"
STATUS=204 DB_PASSWORD=x DB_USER=other run "${F}/17.configurations_database_operations_POST_test.sh"
expect "17 POST: DB_USER replaces the user" "$(printf '%s\n' "${OUT}" | grep -c '^FORM: username=other$')" "1"
run "${F}/17.configurations_database_operations_POST_test.sh"
nothing_sent "17 POST: no DB_PASSWORD, nothing sent"
GET_BODY=

SENTINEL='{"enabled":false,"host":"","port":1305,"heartbeatEnabled":false,"heartbeatDelay":10,"heartbeatTimeUnit":"seconds","overflowFilePath":"","eventStates":{"RECEIVED":"required","DELETED":"false","SENT":"true"}}'
GET_BODY=$(body sentinel "${SENTINEL}")
run "${F}/18.configurations_sentinel_GET.sh"
has "18 GET: on or off, where to, heartbeat" "  enabled: false, to -:1305, heartbeat: false every 10 seconds"
has "18 GET: the states reported" "  states reported: 2 of 3"
STATUS=204 run "${F}/19.configurations_sentinel_PATCH.sh" sentinel.example.com 1306
expect "19 PATCH: reads, then PATCH" "${RC}:$(calls)" "0:GET ${U}/sentinel
PATCH ${U}/sentinel"
expect "19 PATCH: host, port, overflow file, heartbeat, then enabled" "$(payload 1 | jq -c '[.[] | [.path, .value]]')" \
  '[["/host","sentinel.example.com"],["/port",1306],["/overflowFilePath","/tmp/st_sentinel_overflow.dat"],["/heartbeatEnabled",true],["/heartbeatDelay",30],["/enabled",true]]'
run "${F}/19.configurations_sentinel_PATCH.sh"
nothing_sent "19 PATCH: needs a HOST, nothing sent"
run "${F}/19.configurations_sentinel_PATCH.sh" host port
nothing_sent "19 PATCH: PORT must be a number, nothing sent"
GET_BODY=$(body sentinel_on "$(printf '%s' "${SENTINEL}" | jq -c '.enabled = true | .heartbeatEnabled = true | .host = "s"')")
STATUS=204 run "${F}/20.configurations_sentinel_PUT.sh"
expect "20 PUT: reads, then PUT" "${RC}:$(calls)" "0:GET ${U}/sentinel
PUT ${U}/sentinel"
expect "20 PUT: the whole settings, reporting and heartbeat off, the host kept" "$(payload 1 | jq -c '[.enabled, .heartbeatEnabled, .host, .port]')" '[false,false,"s",1305]'
GET_BODY=

LOGIN='{"requirePassword":"optional","userSSO":"disabled","ldapOption":"disabled","adminCertificateOption":"none","adminSSO":"disabled","adminCertificateDepthLimit":10,"certificateIssuer":"other"}'
GET_BODY=$(body login "${LOGIN}")
run "${F}/21.configurations_loginSettings_GET.sh"
has "21 GET: end users and administrators" "  end users: password optional, SSO disabled, LDAP disabled"
STATUS=204 run "${F}/22.configurations_loginSettings_PUT.sh" 9
expect "22 PUT: the whole settings, the depth changed" "${RC}:$(calls | tail -n 1):$(payload 1 | jq -c '[.adminCertificateDepthLimit, .requirePassword, .certificateIssuer]')" \
  "0:PUT ${U}/loginSettings:[9,\"optional\",\"other\"]"
has "22 PUT: prints the value before" "adminCertificateDepthLimit is now 10."
STATUS=400 run "${F}/22.configurations_loginSettings_PUT.sh" 9
expect "22 PUT: a refusal exits 1" "${RC}" "1"
STATUS=204 run "${F}/23.configurations_loginSettings_PATCH.sh" required
expect "23 PATCH: replaces requirePassword" "${RC}:$(calls | tail -n 1):$(payload 1 | jq -c .)" \
  "0:PATCH ${U}/loginSettings:[{\"op\":\"replace\",\"path\":\"/requirePassword\",\"value\":\"required\"}]"
run "${F}/23.configurations_loginSettings_PATCH.sh" disabled
nothing_sent "23 PATCH: VALUE is optional, required or requiredForUserClasses, nothing sent"
GET_BODY=

GET_BODY=$(body zdu '{"zduMaintenanceMode":"disabled"}')
run "${F}/24.configurations_maintenance_GET.sh"
has "24 GET: the mode" "  maintenance mode: disabled"
GET_BODY=
STATUS=204 run "${F}/25.configurations_maintenance_operations_POST.sh" start
expect "25 POST: start" "${RC}:$(calls)" "0:POST ${U}/maintenance/operations?operation=start"
run "${F}/25.configurations_maintenance_operations_POST.sh" pause
nothing_sent "25 POST: start or stop only, nothing sent"

GET_BODY=$(body adminui '{"adminUiConfig":"{\"pages\":{\"Dashboard\":{\"enabledPage\":true},\"Reports\":{\"enabledPage\":false}}}"}')
run "${F}/26.configurations_adminui_GET.sh"
has "26 GET: the pages, from the JSON inside the string" "  Reports: hidden"
GET_BODY=
STATUS_GET=404 run "${F}/27.configurations_allowedSTServers_GET.sh"
expect "27 GET: a 404 says so and exits 1" "${RC}:$(calls)" "1:GET ${U}/allowedSTServers"

STATUS=204 OLD_KEYSTORE_PASSWORD=old-synthetic NEW_KEYSTORE_PASSWORD=new-synthetic run "${F}/28.configurations_keystorePassword_PUT.sh"
expect "28 PUT: the old password and the new one twice" "${RC}:$(calls):$(payload 1 | jq -c '[.oldPassword, .newPassword, .confirmPassword]')" \
  "0:PUT ${U}/keystorePassword:[\"old-synthetic\",\"new-synthetic\",\"new-synthetic\"]"
OLD_KEYSTORE_PASSWORD=old-synthetic run "${F}/28.configurations_keystorePassword_PUT.sh"
nothing_sent "28 PUT: both passwords needed, nothing sent"

ARCHIVING='{"isEnabled":true,"globalArchivingPolicy":"enabled","archiveFolder":"/home/archives","isS3Storage":false,"deleteFilesOlderThan":99,"deleteFilesOlderThanUnit":"days","maximumFileSizeAllowedToArchive":1000}'
GET_BODY=$(body archiving "${ARCHIVING}")
run "${F}/29.configurations_fileArchiving_GET.sh"
has "29 GET: policy and where" "  archiving: enabled, to /home/archives"
has "29 GET: how long and how big" "  files deleted after 99 days, files up to 1000 MB archived"
STATUS=204 run "${F}/30.configurations_fileArchiving_PUT.sh" 500
expect "30 PUT: the whole settings, the size changed" "${RC}:$(calls | tail -n 1):$(payload 1 | jq -c '[.maximumFileSizeAllowedToArchive, .archiveFolder]')" \
  "0:PUT ${U}/fileArchiving:[500,\"/home/archives\"]"
run "${F}/30.configurations_fileArchiving_PUT.sh"
nothing_sent "30 PUT: needs MAX_MB, nothing sent"
STATUS=204 run "${F}/31.configurations_fileArchiving_PATCH.sh" 30
expect "31 PATCH: the days, and the unit days" "${RC}:$(payload 1 | jq -c '[.[] | [.path, .value]]')" \
  '0:[["/deleteFilesOlderThan",30],["/deleteFilesOlderThanUnit","days"]]'
run "${F}/31.configurations_fileArchiving_PATCH.sh" 0
nothing_sent "31 PATCH: DAYS must be 1 or more, nothing sent"
GET_BODY=

GET_BODY=$(body cluster '{"isCluster":false,"clusterMode":null,"clusterNodes":null}')
run "${F}/32.configurations_clusterManagement_GET.sh"
has "32 GET: standalone" "  standalone, not a cluster"
GET_BODY=$(body threshold '{"numberOfNodes":1,"sendNotification":false,"subject":"","notification":""}')
run "${F}/33.configurations_clusterManagement_nodeThreshold_GET.sh"
has "33 GET: nodes and notification" "  expects 1 node(s); notification: false"
GET_BODY=
STATUS=204 run "${F}/34.configurations_clusterManagement_nodeThreshold_PUT.sh" 2
expect "34 PUT: the nodes, with an email" "${RC}:$(calls):$(payload 1 | jq -c '[.numberOfNodes, .sendNotification, (.subject | length > 0)]')" \
  "0:PUT ${U}/clusterManagement/nodeThreshold:[2,true,true]"
STATUS=204 run "${F}/35.configurations_clusterManagement_nodeThreshold_PATCH.sh"
expect "35 PATCH: the email off by default" "${RC}:$(payload 1 | jq -c .)" '0:[{"op":"replace","path":"/sendNotification","value":false}]'
run "${F}/35.configurations_clusterManagement_nodeThreshold_PATCH.sh" yes
nothing_sent "35 PATCH: true or false only, nothing sent"
GET_BODY=$(body replication '{"enabled":false,"subscriptions":[]}')
run "${F}/36.configurations_replication_GET.sh"
has "36 GET: on or off" "  replication: false"
GET_BODY=

STORE='{"name":"example_vault","baseUrl":"http://vault.example.com:8200","uri":"/v1/secret/data","method":"GET","pathPrefix":"$.data.data","cacheTimeout":600,"readTimeout":30,"auth":{"baseUrl":"http://vault.example.com:8200","uri":"/v1/auth/approle/login"}}'
GET_BODY=$(body stores "{\"result\":[${STORE}]}")
run "${F}/37.configurations_externalStores_GET.sh"
expect "37 GET: no filter by default" "$(calls)" "GET ${U}/externalStores"
has "37 GET: one line per store" "  example_vault  http://vault.example.com:8200/v1/secret/data  600s"
run "${F}/37.configurations_externalStores_GET.sh" example_vault
expect "37 GET: an exact name" "$(calls)" "GET ${U}/externalStores?name=example_vault"
GET_BODY=
STATUS=201 VAULT_ROLE_ID=synthetic-role VAULT_SECRET_ID=synthetic-secret run "${F}/38.configurations_externalStores_POST.sh" http://vault.example.com:8200 kv
expect "38 POST: POST /externalStores" "${RC}:$(calls)" "0:POST ${U}/externalStores"
expect "38 POST: the Vault, the KV mount, the KV v2 secret path" "$(payload 1 | jq -c '[.name, .baseUrl, .uri, .pathPrefix]')" \
  '["example_vault","http://vault.example.com:8200","/v1/kv/data","$.data.data"]'
expect "38 POST: the AppRole login, and the token it answers, in the header" \
  "$(payload 1 | jq -c '[.auth.uri, .auth.body.role_id, .auth.body.secret_id, .auth.token, .headers["X-Vault-Token"]]')" \
  '["/v1/auth/approle/login","synthetic-role","synthetic-secret","$.auth.client_token","${vault.api.auth.token}"]'
run "${F}/38.configurations_externalStores_POST.sh" http://vault.example.com:8200
nothing_sent "38 POST: no AppRole credentials, nothing sent"
GET_BODY=$(body store "${STORE}")
run "${F}/39.configurations_externalStores_name_GET.sh"
has "39 GET: what, where, cached" "  example_vault: GET http://vault.example.com:8200/v1/secret/data, secret at \$.data.data, cached 600s"
STATUS=204 run "${F}/40.configurations_externalStores_name_PUT.sh" 11
expect "40 PUT: the whole store, readTimeout changed" "${RC}:$(calls | tail -n 1):$(payload 1 | jq -c '[.readTimeout, .cacheTimeout, .name]')" \
  "0:PUT ${U}/externalStores/example_vault:[11,600,\"example_vault\"]"
STATUS=204 run "${F}/41.configurations_externalStores_name_PATCH.sh" 0 other_store
expect "41 PATCH: cacheTimeout, on the store given" "${RC}:$(calls):$(payload 1 | jq -c .)" \
  "0:PATCH ${U}/externalStores/other_store:[{\"op\":\"replace\",\"path\":\"/cacheTimeout\",\"value\":0}]"
POST_BODY=$(body tested '{"fetchStatus":"Success","connectionStatus":"Success","authenticationStatus":"Success","response":{"statusCode":"200 OK","jsonData":{"username":"****","password":"****"}}}')
STATUS=200 run "${F}/42.configurations_externalStores_name_operations_POST_test.sh" example/db
expect "42 POST: test, with the secret path" "${RC}:$(calls):$(payload 1 | jq -c .)" \
  "0:POST ${U}/externalStores/example_vault/operations?operation=test:{\"secretPath\":\"example/db\"}"
has "42 POST: each step" "  connection: Success, login: Success, fetch: Success"
has "42 POST: the secret's keys, not its values" "  the secret holds: password, username"
POST_BODY=$(body tested_fail '{"fetchStatus":"Failure","connectionStatus":"Success","authenticationStatus":"Success","message":"returned an error"}')
STATUS=200 run "${F}/42.configurations_externalStores_name_operations_POST_test.sh" example/none
expect "42 POST: a failed fetch exits 1, though the answer is 200" "${RC}" "1"
POST_BODY=$(body cleared '{"message":"Cache was cleared successfully"}')
STATUS=200 run "${F}/43.configurations_externalStores_name_operations_POST_clearCache.sh" example/db
expect "43 POST: clearCache, with the secret path" "${RC}:$(calls)" "0:POST ${U}/externalStores/example_vault/operations?operation=clearCache"
has "43 POST: the message" "Cache was cleared successfully"
POST_BODY=
STATUS=204 run "${F}/44.configurations_externalStores_name_DELETE.sh"
expect "44 DELETE: example_vault by default" "${RC}:$(calls)" "0:DELETE ${U}/externalStores/example_vault"
GET_BODY=

REG="${U}/options/StorageProfiles.S3.Registry"
GET_BODY=$(body registry '{"name":"StorageProfiles.S3.Registry","values":["other_s3"]}')
STATUS=204 S3_ACCESS_KEY=synthetic-ak S3_SECRET_KEY=synthetic-sk run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket eu-west-1 http://s3.example.com:9000
expect "45 PUT: reads the registry, adds the profile, sets its options" "${RC}:$(calls)" "0:GET ${REG}
PUT ${U}/options
PUT ${U}/options"
expect "45 PUT: the registry keeps the other profiles" "$(payload 1 | jq -c .)" '[{"name":"StorageProfiles.S3.Registry","values":["example_s3","other_s3"]}]'
expect "45 PUT: the profile's bucket, region, endpoint and keys" "$(payload 2 | jq -c '[.[] | (.name | sub("StorageProfiles.S3.Registry.example_s3."; "")) + "=" + .values[0]]')" \
  '["Bucket=example-bucket","Region=eu-west-1","CustomEndpointUrl=http://s3.example.com:9000","AccessKey=synthetic-ak","SecretKey=synthetic-sk"]'
GET_BODY=$(body registry_empty '{"name":"StorageProfiles.S3.Registry","values":[]}')
STATUS=204 run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket
expect "45 PUT: an empty registry gets just the profile; AWS by default" "$(payload 1 | jq -c '.[0].values'):$(payload 2 | jq -c '[.[1].values[0], .[2].values[0]]')" \
  '["example_s3"]:["us-east-1",""]'
run "${F}/45.configurations_storageProfiles_options_PUT_register.sh"
nothing_sent "45 PUT: needs a BUCKET, nothing sent"
STATUS=204 run "${F}/46.configurations_storageProfiles_name_operations_POST_test.sh"
expect "46 POST: test example_s3" "${RC}:$(calls)" "0:POST ${U}/storageProfiles/example_s3/operations?operation=test"
STATUS=404 run "${F}/46.configurations_storageProfiles_name_operations_POST_test.sh" nope
expect "46 POST: an unknown profile exits 1" "${RC}" "1"
GET_BODY=$(body registry_two '{"values":["example_s3","other_s3"]}')
STATUS=204 run "${F}/47.configurations_storageProfiles_options_PUT_unregister.sh"
expect "47 PUT: the other profiles stay" "$(payload 1 | jq -c .)" '[{"name":"StorageProfiles.S3.Registry","values":["other_s3"]}]'
GET_BODY=$(body registry_one '{"values":["example_s3"]}')
STATUS=204 run "${F}/47.configurations_storageProfiles_options_PUT_unregister.sh"
expect "47 PUT: the last one leaves [\"\"], not []" "$(payload 1 | jq -c '.[0].values')" '[""]'
GET_BODY=

echo
echo "=== 22.DeniedUsers ==="
F=22.DeniedUsers
U="${BASE}/deniedUsers"
DENIED='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"loginName":"example_denied","blockedAt":"Wed, 07 Oct 2026 08:01:03 +0300","blockedUntil":null,"blockedBy":"admin","note":"first"},{"loginName":"example_temp","blockedAt":"Wed, 07 Oct 2026 08:01:03 +0300","blockedUntil":"Wed, 07 Oct 2026 11:01:03 +0300","blockedBy":"admin","note":null}]}'
GET_BODY=$(body denied "${DENIED}")
run "${F}/01.deniedUsers_GET.sh" "example*" 2026-10-07
expect "01 GET: the count, the pattern, permanent, temporary, since" "${RC}:$(calls)" "0:GET ${U}?limit=1&fields=loginName
GET ${U}?loginName=example*
GET ${U}?loginName=example*&isPermanent=true
GET ${U}?loginName=example*&isPermanent=false
GET ${U}?loginName=example*&blockedAt.from=2026-10-07"
has "01 GET: a permanent entry" "  example_denied  permanent  by admin  first"
has "01 GET: a temporary one, with the date it ends and no note" "  example_temp  until Wed, 07 Oct 2026 11:01:03 +0300  by admin  "
run "${F}/01.deniedUsers_GET.sh"
expect "01 GET: every name by default, no since query" "$(calls | sed -n '2p'):$(calls | wc -l | tr -d ' ')" "GET ${U}?loginName=*:4"
run "${F}/01.deniedUsers_GET.sh" "*" 07/10/2026
nothing_sent "01 GET: SINCE must be yyyy-MM-dd, nothing sent"
GET_BODY=

STATUS=201 LOCATION=example_denied run "${F}/02.deniedUsers_POST.sh"
expect "02 POST: POST /deniedUsers" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: permanent by default, so no ttl, and no note" "$(payload 1 | jq -c .)" '{"loginName":"example_denied"}'
has "02 POST: where the entry is, from the Location header" "It is at ${U}/example_denied"
has "02 POST: says for good" "Blocking example_denied for good..."
STATUS=201 LOCATION=x run "${F}/02.deniedUsers_POST.sh" "a name" 5 "why not"
expect "02 POST: a name with a space, ttl as a number, and the note" "$(payload 1 | jq -c .)" '{"loginName":"a name","ttl":5,"note":"why not"}'
has "02 POST: says for how long" "Blocking a name for 5 hours..."
STATUS=400 run "${F}/02.deniedUsers_POST.sh"
expect "02 POST: 'already exists' (400) exits 1" "${RC}" "1"
for BAD in "" " "; do
    run "${F}/02.deniedUsers_POST.sh" "${BAD}"
    [ -z "${BAD}" ] && continue
    nothing_sent "02 POST: a blank LOGIN_NAME is refused, nothing sent"
done
for HOURS in 0 -1 two 1.5; do
    run "${F}/02.deniedUsers_POST.sh" example_denied "${HOURS}"
    nothing_sent "02 POST: HOURS '${HOURS}' is refused, nothing sent"
done

STATUS=204 run "${F}/03.deniedUsers_name_DELETE.sh"
expect "03 DELETE: example_denied by default" "${RC}:$(calls)" "0:DELETE ${U}/example_denied"
STATUS=204 run "${F}/03.deniedUsers_name_DELETE.sh" "a name/with+odd&chars"
expect "03 DELETE: the name goes into the path URL-encoded once" "$(calls)" "DELETE ${U}/a%20name%2Fwith%2Bodd%26chars"
STATUS=400 run "${F}/03.deniedUsers_name_DELETE.sh" example_nope
expect "03 DELETE: a name not in the list (400) exits 1" "${RC}" "1"
run "${F}/03.deniedUsers_name_DELETE.sh" " "
nothing_sent "03 DELETE: a blank LOGIN_NAME is refused, nothing sent"

echo
echo "=== 23.Events ==="
F=23.Events
U="${BASE}/events"
EVENTS='{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"id":"0x000001A114DB4957","status":"active","accountName":"example_user","fullTarget":"/home/example_user/in/a.txt","retryCount":2,"agentType":"advancedRouting","processorType":"ADVANCED_ROUTING"}]}'
GET_BODY=$(body events "${EVENTS}")
run "${F}/01.events_GET.sh" "example*" active
expect "01 GET: the count, the account and status, Advanced Routing only, heartbeat" "${RC}:$(calls | sed 's/lastHeartbeatAfter=[0-9]*/lastHeartbeatAfter=N/')" "0:GET ${U}?limit=1&fields=id
GET ${U}?accountName=example*&status=active
GET ${U}?accountName=example*&processorType=ADVANCED_ROUTING
GET ${U}?accountName=example*&lastHeartbeatAfter=N"
SINCE=$(calls | sed -n 's/.*lastHeartbeatAfter=\([0-9]*\)$/\1/p')
AGE=$(( $(date +%s) * 1000 - SINCE ))
expect "01 GET: the heartbeat limit is an hour ago, in milliseconds" "$(( AGE >= 3600000 && AGE < 3660000 ))" "1"
has "01 GET: one line per event" "  0x000001A114DB4957  active  example_user  /home/example_user/in/a.txt  retries 2"
run "${F}/01.events_GET.sh"
expect "01 GET: every account by default, and no status filter" "$(calls | sed -n '2p')" "GET ${U}?accountName=*"
GET_BODY=

EVENT_ONE='{"id":"0x000001A114DB4957","status":"active","agentType":"advancedRouting","accountName":"example_user","subscriptionId":"sub1","fullTarget":"/home/example_user/in/a.txt","retryCount":2,"recovered":false,"clusterNode":"10.0.0.1"}'
GET_BODY=$(body event_one "${EVENT_ONE}")
run "${F}/02.events_id_GET.sh" 0x000001A114DB4957
expect "02 GET: the event given" "${RC}:$(calls)" "0:GET ${U}/0x000001A114DB4957"
has "02 GET: the summary" "  active advancedRouting event for /home/example_user/in/a.txt"
has "02 GET: account and subscription" "  account example_user, subscription sub1"
GET_BODY=
SEQUENCE=$(sequence event_lookup "${EVENTS}" "${EVENT_ONE}")
run "${F}/02.events_id_GET.sh"
expect "02 GET: no id, so it looks up the first event, then reads it" "$(calls | sed -n '1p;2p')" "GET ${U}?limit=1&fields=id
GET ${U}/0x000001A114DB4957"
SEQUENCE=
GET_BODY=$(body events_none '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')
run "${F}/02.events_id_GET.sh"
expect "02 GET: no events, exit 1, nothing read" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
GET_BODY=
STATUS_GET=404 run "${F}/02.events_id_GET.sh" "a b/c"
expect "02 GET: the id goes into the path URL-encoded once; a 404 exits 1" "${RC}:$(calls)" "1:GET ${U}/a%20b%2Fc"

POST_BODY=$(body deleted '{"events":[{"id":"e1","status":"deleted"},{"id":"nope","status":"not found"}]}')
STATUS=200 run "${F}/03.events_operations_POST_delete.sh" e1 nope
expect "03 POST: operation=delete" "${RC}:$(calls)" "0:POST ${U}/operations?operation=delete"
expect "03 POST: the ids, in order" "$(payload 1 | jq -c .)" '{"ids":["e1","nope"]}'
has "03 POST: what became of each" "  e1: deleted"
has "03 POST: a not found is reported, and does not fail the script" "  nope: not found"
POST_BODY=
STATUS=400 run "${F}/03.events_operations_POST_delete.sh" e1
expect "03 POST: a refusal exits 1" "${RC}" "1"
run "${F}/03.events_operations_POST_delete.sh"
nothing_sent "03 POST: no ids, so nothing is deleted and nothing is sent"

echo
echo "=== 24.IcapServers ==="
F=24.IcapServers
U="${BASE}/icapServers"
FIELDS="serverEnabled%2CbasicSettings.name%2CbasicSettings.type%2CbasicSettings.url"
ICAPS='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"serverEnabled":true,"basicSettings":{"name":"example_icap","type":"INCOMING","url":"icap://h:1344/AVSCAN"}},{"serverEnabled":false,"basicSettings":{"name":"other icap","type":"BOTH","url":"icap://o:1344/REQMOD"}}]}'
GET_BODY=$(body icaps "${ICAPS}")
run "${F}/01.icapServers_GET.sh" example_icap INCOMING
expect "01 GET: the count, all, enabled, one by name, one type" "${RC}:$(calls)" "0:GET ${U}?limit=1&fields=serverEnabled
GET ${U}?fields=${FIELDS//%2C/,}
GET ${U}?serverEnabled=true&fields=${FIELDS//%2C/,}
GET ${U}?basicSettings.name=example_icap&fields=${FIELDS//%2C/,}
GET ${U}?basicSettings.type=INCOMING&fields=${FIELDS//%2C/,}"
has "01 GET: an enabled server" "  example_icap  INCOMING  icap://h:1344/AVSCAN  enabled"
has "01 GET: a disabled one, name with a space" "  other icap  BOTH  icap://o:1344/REQMOD  disabled"
run "${F}/01.icapServers_GET.sh"
expect "01 GET: no name or type, so only three calls" "$(calls | wc -l | tr -d ' ')" "3"
run "${F}/01.icapServers_GET.sh" "" SIDEWAYS
expect "01 GET: an unknown TYPE is refused, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=

STATUS=201 LOCATION=example_icap run "${F}/02.icapServers_POST.sh"
expect "02 POST: POST /icapServers" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: created disabled, with the defaults" "$(payload 1 | jq -c '[.serverEnabled, .basicSettings.name, .basicSettings.type, .basicSettings.url, .basicSettings.maxSize, .basicSettings.previewSize, .basicSettings.denyOnConnectionError]')" \
  '[false,"example_icap","INCOMING","icap://icap.example.com:1344/AVSCAN",10,1024,false]'
has "02 POST: where it is, from Location" "It is at ${U}/example_icap"
STATUS=201 LOCATION=x run "${F}/02.icapServers_POST.sh" "a name" icap://h:1344/REQMOD BOTH
expect "02 POST: a name with a space, the address and type given" "$(payload 1 | jq -c '[.basicSettings.name, .basicSettings.url, .basicSettings.type]')" '["a name","icap://h:1344/REQMOD","BOTH"]'
STATUS=409 run "${F}/02.icapServers_POST.sh"
expect "02 POST: a name that exists (409) exits 1" "${RC}" "1"
for ARGS in "a/b" "a;b" "a'b" "x http://h/s" "x icap://h INCOMING" "x icap://h/s SIDEWAYS"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "${F}/02.icapServers_POST.sh" "$@"
    nothing_sent "02 POST: refuses '${ARGS}', nothing sent"
done
run "${F}/02.icapServers_POST.sh" " "
nothing_sent "02 POST: a blank NAME is refused, nothing sent"

run "${F}/03.icapServers_name_HEAD.sh"
expect "03 HEAD: example_icap by default" "${RC}:$(calls)" "0:HEAD ${U}/example_icap"
STATUS=404 run "${F}/03.icapServers_name_HEAD.sh" "a name"
expect "03 HEAD: a name with a space is encoded; 404 exits 1" "${RC}:$(calls)" "1:HEAD ${U}/a%20name"

ICAP='{"serverEnabled":true,"basicSettings":{"name":"example_icap","type":"INCOMING","url":"icap://h:1344/AVSCAN","maxSize":10,"previewSize":1024,"denyOnConnectionError":true},"scanFilteringSettings":{"policyExpression":""},"metadata":{"links":{}}}'
BUS='{"result":[{"name":"unit_a","enabledIcapServers":["example_icap","x"]},{"name":"unit_b","enabledIcapServers":["x"]},{"name":"unit_c"}]}'
SEQUENCE=$(sequence icap_one "${ICAP}" "${BUS}")
run "${F}/04.icapServers_name_GET.sh"
expect "04 GET: the server, then the business units" "${RC}:$(calls)" "0:GET ${U}/example_icap
GET ${BASE}/businessUnits?limit=500&fields=name,enabledIcapServers"
has "04 GET: the summary" "  example_icap: INCOMING icap://h:1344/AVSCAN, enabled"
has "04 GET: the limits and what happens when unreachable" "  when it cannot be reached: the transfer is denied"
has "04 GET: no scan policy means every transfer" "  scan policy: none, every transfer"
expect "04 GET: only the units that list it" "$(printf '%s\n' "${OUT}" | grep -c '^  unit_')" "1"
has "04 GET: that unit" "  unit_a"
SEQUENCE=
STATUS_GET=404 run "${F}/04.icapServers_name_GET.sh" "a name"
expect "04 GET: a missing server (404) exits 1, encoded" "${RC}:$(calls | head -n 1)" "1:GET ${U}/a%20name"

GET_BODY=$(body icap_put "${ICAP}")
STATUS=204 run "${F}/05.icapServers_name_PUT.sh" example_icap 25
expect "05 PUT: reads, then PUT" "${RC}:$(calls)" "0:GET ${U}/example_icap
PUT ${U}/example_icap"
expect "05 PUT: the whole server, maxSize changed, metadata dropped" "$(payload 1 | jq -c '[.basicSettings.maxSize, .basicSettings.previewSize, .serverEnabled, has("metadata")]')" '[25,1024,true,false]'
has "05 PUT: prints the value before" "maxSize of example_icap is now 10 MB."
STATUS=204 run "${F}/05.icapServers_name_PUT.sh" "other icap" 5
expect "05 PUT: the name stays the one in the path, so it cannot rename" "$(payload 1 | jq -r '.basicSettings.name')" "other icap"
run "${F}/05.icapServers_name_PUT.sh" example_icap many
nothing_sent "05 PUT: MAX_MB must be a number, nothing sent"
GET_BODY=
STATUS=400 run "${F}/05.icapServers_name_PUT.sh"
expect "05 PUT: no such server, exit 1, nothing put" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"

STATUS=204 run "${F}/06.icapServers_name_PATCH.sh" example_icap true true
expect "06 PATCH: PATCH the server" "${RC}:$(calls)" "0:PATCH ${U}/example_icap"
expect "06 PATCH: enabled, and deny when unreachable" "$(payload 1 | jq -c '[.[] | [.path, .value]]')" '[["/serverEnabled",true],["/basicSettings/denyOnConnectionError",true]]'
STATUS=204 run "${F}/06.icapServers_name_PATCH.sh"
expect "06 PATCH: off by default, and the deny setting left alone" "$(payload 1 | jq -c '[.[] | [.path, .value]]')" '[["/serverEnabled",false]]'
run "${F}/06.icapServers_name_PATCH.sh" example_icap maybe
nothing_sent "06 PATCH: ENABLED is true or false, nothing sent"
run "${F}/06.icapServers_name_PATCH.sh" example_icap true 1
nothing_sent "06 PATCH: DENY_ON_ERROR is true or false, nothing sent"
STATUS=404 run "${F}/06.icapServers_name_PATCH.sh" nope
expect "06 PATCH: no such server (404) exits 1" "${RC}" "1"

STATUS=204 run "${F}/07.icapServers_name_DELETE.sh"
expect "07 DELETE: example_icap by default" "${RC}:$(calls)" "0:DELETE ${U}/example_icap"
STATUS=204 run "${F}/07.icapServers_name_DELETE.sh" "a name/x"
expect "07 DELETE: the name is URL-encoded once" "$(calls)" "DELETE ${U}/a%20name%2Fx"
STATUS=404 run "${F}/07.icapServers_name_DELETE.sh" nope
expect "07 DELETE: not found (404) exits 1" "${RC}" "1"

echo
echo "=== 25.LdapDomains ==="
F=25.LdapDomains
U="${BASE}/ldapDomains"
LFIELDS="name,ldapServers,ldapSearches.baseDn,isDefault"
LDAPS='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"name":"example_ldap","isDefault":false,"ldapServers":[{"host":"10.0.0.1","port":389},{"host":"10.0.0.2","port":636}],"ldapSearches":{"baseDn":"ou=People,dc=example,dc=com"}},{"name":"other ldap","isDefault":true,"ldapServers":[{"host":"h","port":389}],"ldapSearches":{"baseDn":null}}]}'
GET_BODY=$(body ldaps "${LDAPS}")
run "${F}/01.ldapDomains_GET.sh" example_ldap 3
expect "01 GET: the count, all, one by name, one protocol version" "${RC}:$(calls)" "0:GET ${U}?limit=1&fields=name
GET ${U}?fields=${LFIELDS}
GET ${U}?name=example_ldap&fields=${LFIELDS}
GET ${U}?protocolVersion=3&fields=${LFIELDS}"
has "01 GET: a domain with two servers" "  example_ldap  10.0.0.1:389, 10.0.0.2:636  ou=People,dc=example,dc=com  -"
has "01 GET: the default domain, with no base DN" "  other ldap  h:389  -  default"
run "${F}/01.ldapDomains_GET.sh"
expect "01 GET: no name or version, so two calls after the count" "$(calls | wc -l | tr -d ' ')" "2"
run "${F}/01.ldapDomains_GET.sh" "" 4
expect "01 GET: PROTOCOL_VERSION is 2 or 3, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=

STATUS=201 LOCATION=8a05id LDAP_BIND_PASSWORD=synthetic-bind run "${F}/02.ldapDomains_POST.sh"
expect "02 POST: POST /ldapDomains" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: the name, the ST server as the directory, port 389, the bind account and password" \
  "$(payload 1 | jq -c '[.name, .ldapServers[0].host, .ldapServers[0].port, .bindDn, .bindDnPassword, .protocolVersion]')" \
  '["example_ldap","st.example.com",389,"cn=reader,dc=example,dc=com","synthetic-bind",3]'
expect "02 POST: where it searches" "$(payload 1 | jq -c '[.ldapSearches.baseDn, .ldapSearches.searchAttribute]')" '["ou=People,dc=example,dc=com","UID"]'
has "02 POST: the domain's id, from the end of Location" "Its id: 8a05id"
STATUS=201 LOCATION=x LDAP_BIND_PASSWORD=synthetic-bind run "${F}/02.ldapDomains_POST.sh" "a name" 10.1.2.3 1389
expect "02 POST: a name with a space, the host and port given" "$(payload 1 | jq -c '[.name, .ldapServers[0].host, .ldapServers[0].port]')" '["a name","10.1.2.3",1389]'
STATUS=400 LDAP_BIND_PASSWORD=synthetic-bind run "${F}/02.ldapDomains_POST.sh" example_ldap no.such.host
expect "02 POST: a refusal (400, host cannot be resolved) exits 1" "${RC}" "1"
run "${F}/02.ldapDomains_POST.sh"
nothing_sent "02 POST: no LDAP_BIND_PASSWORD, nothing sent"
for ARGS in "x h 70000" "x h port" "x h -1"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    LDAP_BIND_PASSWORD=synthetic-bind run "${F}/02.ldapDomains_POST.sh" "$@"
    nothing_sent "02 POST: refuses '${ARGS}', nothing sent"
done
LDAP_BIND_PASSWORD=synthetic-bind run "${F}/02.ldapDomains_POST.sh" " "
nothing_sent "02 POST: a blank NAME is refused, nothing sent"

run "${F}/03.ldapDomains_name_HEAD.sh"
expect "03 HEAD: example_ldap by default" "${RC}:$(calls)" "0:HEAD ${U}/example_ldap"
STATUS=404 run "${F}/03.ldapDomains_name_HEAD.sh" "a name"
expect "03 HEAD: a name with a space is encoded; 404 exits 1" "${RC}:$(calls)" "1:HEAD ${U}/a%20name"

DOMAIN='{"id":"d1","name":"example_ldap","description":"old description","isDefault":false,"protocolVersion":3,"bindDn":"cn=reader,dc=example,dc=com","bindDnPassword":"{AES128}abc==","ldapServers":[{"id":"s1","host":"10.0.0.1","port":389,"order":1},{"id":"s2","host":"10.0.0.2","port":636,"order":2}],"ldapSearches":{"baseDn":"ou=People,dc=example,dc=com","searchAttribute":"UID"},"sslEnabled":false,"tlsEnabled":false,"referralsAllowed":true,"anonymousBindsAllowed":true,"metadata":{"links":{}}}'
GET_BODY=$(body ldap_one "${DOMAIN}")
run "${F}/04.ldapDomains_name_GET.sh"
expect "04 GET: reads the domain" "${RC}:$(calls)" "0:GET ${U}/example_ldap"
has "04 GET: the summary" "  example_ldap: LDAP version 3, not the default"
has "04 GET: each server, with its id" "  server 2: 10.0.0.2:636, id s2"
has "04 GET: the bind account and where it searches" "  bind as cn=reader,dc=example,dc=com, search ou=People,dc=example,dc=com by UID"
STATUS_GET=404 run "${F}/04.ldapDomains_name_GET.sh" "a name"
expect "04 GET: a missing domain (404) exits 1, encoded" "${RC}:$(calls | head -n 1)" "1:GET ${U}/a%20name"

STATUS=204 run "${F}/05.ldapDomains_name_PUT.sh" example_ldap "new text"
expect "05 PUT: reads, then PUT" "${RC}:$(calls)" "0:GET ${U}/example_ldap
PUT ${U}/example_ldap"
expect "05 PUT: the new description, the name, and metadata dropped" "$(payload 1 | jq -c '[.description, .name, has("metadata")]')" '["new text","example_ldap",false]'
expect "05 PUT: the encrypted password goes back exactly as it was read, with both servers" "$(payload 1 | jq -c '[.bindDnPassword, (.ldapServers | length)]')" '["{AES128}abc==",2]'
has "05 PUT: prints the description before" "The description of example_ldap is now: old description"
STATUS=204 run "${F}/05.ldapDomains_name_PUT.sh" "other ldap" x
expect "05 PUT: the name stays the one in the path, so it cannot rename" "$(payload 1 | jq -r .name)" "other ldap"
GET_BODY=
STATUS=400 run "${F}/05.ldapDomains_name_PUT.sh"
expect "05 PUT: no such domain, exit 1, nothing put" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"

STATUS=204 run "${F}/06.ldapDomains_name_PATCH.sh" example_ldap "words" 390
expect "06 PATCH: PATCH the domain" "${RC}:$(calls)" "0:PATCH ${U}/example_ldap"
expect "06 PATCH: the description and the first server's port" "$(payload 1 | jq -c '[.[] | [.path, .value]]')" '[["/description","words"],["/ldapServers/0/port",390]]'
STATUS=204 run "${F}/06.ldapDomains_name_PATCH.sh"
expect "06 PATCH: only the description by default" "$(payload 1 | jq -c '[.[] | .path]')" '["/description"]'
run "${F}/06.ldapDomains_name_PATCH.sh" example_ldap x 70000
nothing_sent "06 PATCH: PORT is a number up to 65535, nothing sent"
STATUS=404 run "${F}/06.ldapDomains_name_PATCH.sh" nope
expect "06 PATCH: no such domain (404) exits 1" "${RC}" "1"

STATUS=204 run "${F}/07.ldapDomains_name_DELETE.sh"
expect "07 DELETE: example_ldap by default" "${RC}:$(calls)" "0:DELETE ${U}/example_ldap"
STATUS=204 run "${F}/07.ldapDomains_name_DELETE.sh" "a name/x"
expect "07 DELETE: the name is URL-encoded once" "$(calls)" "DELETE ${U}/a%20name%2Fx"
STATUS=404 run "${F}/07.ldapDomains_name_DELETE.sh" nope
expect "07 DELETE: not found (404) exits 1" "${RC}" "1"

GET_BODY=$(body ldap_one "${DOMAIN}")
POST_BODY=$(body tested_ok '{"message":"Successful Connection."}')
STATUS=200 run "${F}/08.ldapDomains_name_operations_POST_testConnection.sh"
expect "08 POST: looks the domain up, then testConnection" "${RC}:$(calls)" "0:GET ${U}/example_ldap
POST ${U}/example_ldap/operations?operation=testConnection"
expect "08 POST: the id of the first server" "$(payload 1 | jq -c .)" '{"id":"s1"}'
has "08 POST: the message" "Successful Connection."
STATUS=200 run "${F}/08.ldapDomains_name_operations_POST_testConnection.sh" example_ldap 2
expect "08 POST: the second server, by its number" "$(payload 1 | jq -c .)" '{"id":"s2"}'
POST_BODY=$(body tested_fail '{"message":"Connection failed."}')
STATUS=200 run "${F}/08.ldapDomains_name_operations_POST_testConnection.sh"
expect "08 POST: a failed connection, though the answer is 200, exits 1" "${RC}" "1"
has "08 POST: and says so" "Connection failed."
run "${F}/08.ldapDomains_name_operations_POST_testConnection.sh" example_ldap 3
expect "08 POST: no server 3, exit 1, nothing posted" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
run "${F}/08.ldapDomains_name_operations_POST_testConnection.sh" example_ldap 0
nothing_sent "08 POST: SERVER_NUMBER is 1 or more, nothing sent"
POST_BODY=
GET_BODY=

echo
echo "=== 26.LoginRestrictionPolicies ==="
F=26.LoginRestrictionPolicies
U="${BASE}/loginRestrictionPolicies"
LRPF="name,type,isDefault,rules,businessUnit"
POLICIES='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"name":"example_lrp","type":"ALLOW_THEN_DENY","isDefault":false,"rules":[{"name":"a"},{"name":"b"}],"businessUnits":["unit one","unit two"]},{"name":"main policy","type":"DENY_THEN_ALLOW","isDefault":true,"rules":[],"businessUnits":[]}]}'
GET_BODY=$(body policies "${POLICIES}")
run "${F}/01.loginRestrictionPolicies_GET.sh" "example*" DENY_THEN_ALLOW
expect "01 GET: the count, by name, by type, the default policy" "${RC}:$(calls)" "0:GET ${U}?limit=1&fields=name
GET ${U}?name=example*&fields=${LRPF}
GET ${U}?type=DENY_THEN_ALLOW&fields=${LRPF}
GET ${U}?isDefault=true&fields=${LRPF}"
has "01 GET: a policy with two rules and two business units" "  example_lrp  ALLOW_THEN_DENY  2 rule(s)  business units: unit one, unit two"
has "01 GET: the default policy, with nothing assigned" "  main policy  DENY_THEN_ALLOW  0 rule(s)  default  business units: -"
run "${F}/01.loginRestrictionPolicies_GET.sh"
expect "01 GET: every name by default, no type query" "$(calls | sed -n '2p'):$(calls | wc -l | tr -d ' ')" "GET ${U}?name=*&fields=${LRPF}:3"
run "${F}/01.loginRestrictionPolicies_GET.sh" "*" SIDEWAYS
expect "01 GET: an unknown TYPE is refused, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=

STATUS=201 LOCATION=example_lrp run "${F}/02.loginRestrictionPolicies_POST.sh"
expect "02 POST: POST /loginRestrictionPolicies" "${RC}:$(calls)" "0:POST ${U}"
expect "02 POST: example_lrp, ALLOW_THEN_DENY, and no rules or business units in the body" "$(payload 1 | jq -c .)" '{"name":"example_lrp","type":"ALLOW_THEN_DENY"}'
has "02 POST: where it is, from Location" "It is at ${U}/example_lrp"
STATUS=201 LOCATION=x run "${F}/02.loginRestrictionPolicies_POST.sh" "a name" DENY_THEN_ALLOW "why"
expect "02 POST: a name with a space, the type and description given" "$(payload 1 | jq -c .)" '{"name":"a name","type":"DENY_THEN_ALLOW","description":"why"}'
STATUS=409 run "${F}/02.loginRestrictionPolicies_POST.sh"
expect "02 POST: a name that exists (409) exits 1" "${RC}" "1"
for ARGS in "a/b" "a;b" "a'b" "x SIDEWAYS"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "${F}/02.loginRestrictionPolicies_POST.sh" "$@"
    nothing_sent "02 POST: refuses '${ARGS}', nothing sent"
done
run "${F}/02.loginRestrictionPolicies_POST.sh" " "
nothing_sent "02 POST: a blank NAME is refused, nothing sent"

run "${F}/03.loginRestrictionPolicies_name_HEAD.sh"
expect "03 HEAD: example_lrp by default" "${RC}:$(calls)" "0:HEAD ${U}/example_lrp"
STATUS=404 run "${F}/03.loginRestrictionPolicies_name_HEAD.sh" "a name"
expect "03 HEAD: a name with a space is encoded; 404 exits 1" "${RC}:$(calls)" "1:HEAD ${U}/a%20name"

POLICY='{"id":"p1","name":"example_lrp","type":"ALLOW_THEN_DENY","description":"old","isDefault":false,"rules":[{"id":"r1","name":"a","type":"DENY","clientAddress":"10.0.0.1","isEnabled":true,"expression":""},{"id":"r2","name":"b","type":"ALLOW","clientAddress":"*","isEnabled":false,"expression":"${currentSessions <= 3}"},{"id":"r3","name":"c","type":"DENY","clientAddress":"*.example.com","isEnabled":true,"expression":""}],"businessUnits":["unit one","unit two"],"metadata":{"links":{}}}'
GET_BODY=$(body policy_one "${POLICY}")
run "${F}/04.loginRestrictionPolicies_name_GET.sh"
expect "04 GET: reads the policy" "${RC}:$(calls)" "0:GET ${U}/example_lrp"
has "04 GET: the summary" "  example_lrp: ALLOW_THEN_DENY, not the default"
has "04 GET: the business units" "  business units: unit one, unit two"
has "04 GET: a disabled rule with a condition" '    b  ALLOW  *  disabled  ${currentSessions <= 3}'
has "04 GET: an enabled rule with no condition" "    c  DENY  *.example.com  enabled  -"
STATUS_GET=404 run "${F}/04.loginRestrictionPolicies_name_GET.sh" "a name"
expect "04 GET: a missing policy (404) exits 1, encoded" "${RC}:$(calls | head -n 1)" "1:GET ${U}/a%20name"

STATUS=204 run "${F}/05.loginRestrictionPolicies_name_PUT.sh" example_lrp "new text"
expect "05 PUT: reads, then PUT" "${RC}:$(calls)" "0:GET ${U}/example_lrp
PUT ${U}/example_lrp"
expect "05 PUT: the new description, the name, metadata dropped" "$(payload 1 | jq -c '[.description, .name, has("metadata")]')" '["new text","example_lrp",false]'
expect "05 PUT: the rules and business units go back, so nothing is lost" "$(payload 1 | jq -c '[(.rules | length), .businessUnits]')" '[3,["unit one","unit two"]]'
has "05 PUT: prints the description before" "The description of example_lrp is now: old"
STATUS=204 run "${F}/05.loginRestrictionPolicies_name_PUT.sh" "other policy" x
expect "05 PUT: the name stays the one in the path, so it cannot rename" "$(payload 1 | jq -r .name)" "other policy"
GET_BODY=
STATUS=404 run "${F}/05.loginRestrictionPolicies_name_PUT.sh"
expect "05 PUT: no such policy, exit 1, nothing put" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"

STATUS=204 run "${F}/06.loginRestrictionPolicies_name_PATCH.sh"
expect "06 PATCH: PATCH the policy" "${RC}:$(calls)" "0:PATCH ${U}/example_lrp"
expect "06 PATCH: a DENY rule for the example host name, at /rules/-, with no condition" \
  "$(payload 1 | jq -c '[.[0].op, .[0].path, .[0].value.name, .[0].value.type, .[0].value.clientAddress, .[0].value.isEnabled, (.[0].value | has("expression"))]')" \
  '["add","/rules/-","example rule","DENY","client.example.com",true,false]'
STATUS=204 run "${F}/06.loginRestrictionPolicies_name_PATCH.sh" "a policy" "office" ALLOW 10.0.0.0/24 '${currentSessions <= 3}'
expect "06 PATCH: the policy, rule, type, address and condition given" "$(calls):$(payload 1 | jq -c '[.[0].value.name, .[0].value.type, .[0].value.clientAddress, .[0].value.expression]')" \
  "PATCH ${U}/a%20policy:[\"office\",\"ALLOW\",\"10.0.0.0/24\",\"\${currentSessions <= 3}\"]"
STATUS=400 run "${F}/06.loginRestrictionPolicies_name_PATCH.sh" example_lrp bad DENY "not an address"
expect "06 PATCH: a refused address (400) exits 1" "${RC}" "1"
for ARGS in "example_lrp a/b" "example_lrp r MAYBE"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "${F}/06.loginRestrictionPolicies_name_PATCH.sh" "$@"
    nothing_sent "06 PATCH: refuses '${ARGS}', nothing sent"
done

STATUS=204 run "${F}/07.loginRestrictionPolicies_name_DELETE.sh"
expect "07 DELETE: example_lrp by default" "${RC}:$(calls)" "0:DELETE ${U}/example_lrp"
STATUS=204 run "${F}/07.loginRestrictionPolicies_name_DELETE.sh" "a name/x"
expect "07 DELETE: the name is URL-encoded once" "$(calls)" "DELETE ${U}/a%20name%2Fx"
STATUS=404 run "${F}/07.loginRestrictionPolicies_name_DELETE.sh" nope
expect "07 DELETE: not found (404) exits 1" "${RC}" "1"

GET_BODY=$(body policy_rules "${POLICY}")
STATUS=204 run "${F}/08.loginRestrictionPolicies_name_PATCH_rule.sh" example_lrp b enable
expect "08 PATCH: reads the policy, then patches" "${RC}:$(calls)" "0:GET ${U}/example_lrp
PATCH ${U}/example_lrp"
expect "08 PATCH: enable rule b, which is at position 1" "$(payload 1 | jq -c '[.[0].op, .[0].path, .[0].value]')" '["replace","/rules/1/isEnabled",true]'
STATUS=204 run "${F}/08.loginRestrictionPolicies_name_PATCH_rule.sh" example_lrp c
expect "08 PATCH: disable by default, rule c at position 2" "$(payload 1 | jq -c '[.[0].path, .[0].value]')" '["/rules/2/isEnabled",false]'
STATUS=204 run "${F}/08.loginRestrictionPolicies_name_PATCH_rule.sh" example_lrp a remove
expect "08 PATCH: remove rule a, at position 0" "$(payload 1 | jq -c '[.[0].op, .[0].path, (.[0] | has("value"))]')" '["remove","/rules/0",false]'
run "${F}/08.loginRestrictionPolicies_name_PATCH_rule.sh" example_lrp nosuch
expect "08 PATCH: no such rule, exit 1, nothing patched" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
run "${F}/08.loginRestrictionPolicies_name_PATCH_rule.sh" example_lrp a explode
nothing_sent "08 PATCH: ACTION is enable, disable or remove, nothing sent"

STATUS=204 run "${F}/09.loginRestrictionPolicies_name_PATCH_businessUnit.sh" example_lrp "unit three"
expect "09 PATCH: assign adds to /businessUnits/-, with no read first" "${RC}:$(calls):$(payload 1 | jq -c '[.[0].op, .[0].path, .[0].value]')" \
  '0:PATCH '"${U}"'/example_lrp:["add","/businessUnits/-","unit three"]'
STATUS=204 run "${F}/09.loginRestrictionPolicies_name_PATCH_businessUnit.sh" example_lrp "unit two" remove
expect "09 PATCH: take away unit two, which is at position 1" "$(calls | wc -l | tr -d ' '):$(payload 1 | jq -c '[.[0].op, .[0].path]')" '2:["remove","/businessUnits/1"]'
run "${F}/09.loginRestrictionPolicies_name_PATCH_businessUnit.sh" example_lrp "unit nine" remove
expect "09 PATCH: not assigned, exit 1, nothing patched" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
run "${F}/09.loginRestrictionPolicies_name_PATCH_businessUnit.sh" example_lrp
nothing_sent "09 PATCH: the unit is required, nothing sent"
run "${F}/09.loginRestrictionPolicies_name_PATCH_businessUnit.sh" example_lrp unit sideways
nothing_sent "09 PATCH: add or remove only, nothing sent"
GET_BODY=

echo
echo "=== 16.TransferLogs (03 to 05), 27.AuditLogs, 28.ServerLogs ==="
T="${BASE}/logs/transfers"
LIST_ONE='{"result":[{"id":{"mTransferStatusId":"t1","urlrepresentation":"QWJj"}}]}'
TRANSFER='{"status":"Processed","file":"a.txt","transferType":"User upload","duration":"81 ms","account":"example_user","login":"example_user","serverName":"Http Default","transferSite":"(none)","startTime":"Wed, 07 Oct 2026 10:33:12 +0300","isCancelable":false,"isResubmittable":true}'
STATUS=200 run "16.TransferLogs/03.logs_transfers_id_GET.sh" "QWJj"
expect "03 GET: the transfer given" "${RC}:$(calls)" "0:GET ${T}/QWJj"
SEQUENCE=$(sequence tl_newest "${LIST_ONE}" "${TRANSFER}")
run "16.TransferLogs/03.logs_transfers_id_GET.sh"
expect "03 GET: no id, so the newest is looked up, then read" "$(calls)" "GET ${T}?sortByStartTime=descending&limit=1&fields=id
GET ${T}/QWJj"
SEQUENCE=
GET_BODY=$(body tl_one "${TRANSFER}")
run "16.TransferLogs/03.logs_transfers_id_GET.sh" QWJj
has "03 GET: the status, file, type and duration" "  Processed: a.txt (User upload), 81 ms"
has "03 GET: who, where, which site" "  account example_user, login example_user, server Http Default, site (none)"
has "03 GET: whether the server will allow a cancel or a resubmit" "  cancelable: no, resubmittable: yes"
GET_BODY=$(body tl_one_cancelable "$(printf '%s' "${TRANSFER}" | jq -c '.isCancelable = true | .isResubmittable = false')")
run "16.TransferLogs/03.logs_transfers_id_GET.sh" QWJj
has "03 GET: and the other way round" "  cancelable: yes, resubmittable: no"
GET_BODY=$(body tl_one "${TRANSFER}")
GET_BODY=$(body tl_none '{"result":[]}')
run "16.TransferLogs/03.logs_transfers_id_GET.sh"
expect "03 GET: no transfers, exit 1, nothing read" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
GET_BODY=
STATUS_GET=400 run "16.TransferLogs/03.logs_transfers_id_GET.sh" "bad id"
expect "03 GET: a refused id (400) exits 1" "${RC}" "1"

POST_BODY=$(body tl_resubmitted '{"message":"Transfer with id t1 was successfully resubmitted."}')
STATUS=200 run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" QWJj resubmit
expect "04 POST: resubmit, with no body" "${RC}:$(calls):$(payload 1)" "0:POST ${T}/QWJj/operations?operation=resubmit:"
has "04 POST: the answer's message" "Transfer with id t1 was successfully resubmitted."
STATUS=200 run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" QWJj ack "all good"
expect "04 POST: ack, with the message in the body" "$(calls):$(payload 1 | jq -c .)" "POST ${T}/QWJj/operations?operation=ack:{\"userMessage\":\"all good\"}"
STATUS=200 run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" QWJj nack
expect "04 POST: nack with no message sends no body" "$(payload 1)" ""
STATUS=200 run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" QWJj cancel "ignored"
expect "04 POST: a message is sent only with ack and nack" "$(payload 1)" ""
POST_BODY=$(body tl_refused '{"message":"Transfer with id x is not eligible for cancellation."}')
STATUS=400 run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" QWJj cancel
expect "04 POST: a refusal (400) exits 1, and shows why" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'not eligible for cancellation')" "1:1"
POST_BODY=
for ARGS in "" "QWJj" "QWJj explode" "x delete"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "16.TransferLogs/04.logs_transfers_id_operations_POST.sh" "$@"
    nothing_sent "04 POST: refuses '${ARGS}', nothing sent"
done

GET_BODY=$(body tl_pull '{"totalCount":3,"successful":2,"failed":1,"inRetry":0,"inProgress":0,"onHold":0}')
run "16.TransferLogs/05.logs_transfers_pullSummary_GET.sh" "9eb3 d677"
expect "05 GET: the index is URL-encoded once" "${RC}:$(calls)" "0:GET ${T}/pullSummary/9eb3%20d677"
has "05 GET: the counts" "  3 file(s): 2 pulled, 1 failed, 0 to retry, 0 in progress, 0 on hold"
STATUS_GET=404 run "16.TransferLogs/05.logs_transfers_pullSummary_GET.sh" nope
expect "05 GET: a refusal exits 1" "${RC}" "1"
run "16.TransferLogs/05.logs_transfers_pullSummary_GET.sh"
nothing_sent "05 GET: the index is required, nothing sent"
GET_BODY=

A="${BASE}/logs/audit"
AFIELDS="id,dateModified,operationType,objectType,objectName,userName,remoteAddress"
AUDITS='{"resultSet":{"returnCount":1,"totalCount":6081},"result":[{"id":"a1","dateModified":"Wed, 07 Oct 2026 10:27:34 +0300","operationType":"CREATE","objectType":"BusinessUnit","objectName":"example_bu","userName":"admin","remoteAddress":"1.2.3.4"}]}'
GET_BODY=$(body audits "${AUDITS}")
run "27.AuditLogs/01.logs_audit_GET.sh" 6 BusinessUnit example_bu CREATE
expect "01 GET: the count, the last hours, the latest 5, then the filtered 10" "${RC}:$(calls)" "0:GET ${A}?limit=1&fields=id
GET ${A}?duration=6&limit=1&fields=id
GET ${A}?duration=6&limit=5&fields=${AFIELDS}
GET ${A}?objectType=BusinessUnit&objectName=example_bu&operationType=CREATE&limit=10&fields=${AFIELDS}"
has "01 GET: an entry, who, from where" "  Wed, 07 Oct 2026 10:27:34 +0300  CREATE  BusinessUnit example_bu  by admin from 1.2.3.4"
run "27.AuditLogs/01.logs_audit_GET.sh"
expect "01 GET: 24 hours and no filter by default, so three calls" "$(calls | sed -n '2p'):$(calls | wc -l | tr -d ' ')" "GET ${A}?duration=24&limit=1&fields=id:3"
for ARGS in "0" "x" "24 T n EXPLODE"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "27.AuditLogs/01.logs_audit_GET.sh" "$@"
    nothing_sent "01 GET: refuses '${ARGS}', nothing sent"
done
ENTRY='{"id":"a1","dateModified":"Wed, 07 Oct 2026 10:27:34 +0300","configurationId":"c1","operationType":"CREATE","objectType":"BusinessUnit","objectName":"example_bu","userName":"admin","remoteAddress":"1.2.3.4","description":"Business unit created","metadata":{"links":{}}}'
GET_BODY=$(body audit_one "${ENTRY}")
run "27.AuditLogs/02.logs_audit_id_GET.sh" "a 1"
expect "02 GET: the id is URL-encoded once" "${RC}:$(calls)" "0:GET ${A}/a%201"
has "02 GET: the summary" "  CREATE BusinessUnit example_bu, Wed, 07 Oct 2026 10:27:34 +0300"
has "02 GET: who and from where" "  by admin from 1.2.3.4 (no user agent)"
GET_BODY=
SEQUENCE=$(sequence audit_newest '{"result":[{"id":"a1"}]}' "${ENTRY}")
run "27.AuditLogs/02.logs_audit_id_GET.sh"
expect "02 GET: no id, so the newest is looked up, then read" "$(calls)" "GET ${A}?limit=1&fields=id
GET ${A}/a1"
SEQUENCE=
STATUS_GET=404 run "27.AuditLogs/02.logs_audit_id_GET.sh" nope
expect "02 GET: a missing entry (404) exits 1" "${RC}" "1"

SEQUENCE=$(sequence audit_put "${ENTRY}" "${ENTRY}")
STATUS=204 run "27.AuditLogs/03.logs_audit_id_PUT.sh" a1 "a new text"
expect "03 PUT: reads, PUTs, reads again" "${RC}:$(calls)" "0:GET ${A}/a1
PUT ${A}/a1
GET ${A}/a1"
expect "03 PUT: the whole entry back, the new description, metadata dropped" "$(payload 1 | jq -c '[.description, .configurationId, .operationType, .dateModified, has("metadata")]')" '["a new text","c1","CREATE","Wed, 07 Oct 2026 10:27:34 +0300",false]'
has "03 PUT: says the audit log cannot be edited, when the description is as it was" "It did not change: the audit log cannot be edited."
SEQUENCE=$(sequence audit_put_changed "${ENTRY}" "$(printf '%s' "${ENTRY}" | jq -c '.description = "a new text"')")
STATUS=204 run "27.AuditLogs/03.logs_audit_id_PUT.sh" a1 "a new text"
expect "03 PUT: and says nothing of the kind when it did change" "$(printf '%s\n' "${OUT}" | grep -c 'cannot be edited')" "0"
SEQUENCE=
run "27.AuditLogs/03.logs_audit_id_PUT.sh"
nothing_sent "03 PUT: the id is required, nothing sent"
GET_BODY=$(body audit_none '{"message":"not found"}')
run "27.AuditLogs/03.logs_audit_id_PUT.sh" nope
expect "03 PUT: no such entry, exit 1, nothing put" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
GET_BODY=$(body audit_csv 'User Name, Remote Host, Date Modified
"admin","1.2.3.4","20261007102734"
"admin","1.2.3.4","20261007102735"')
STATUS=200 STATUS_GET=200 run "27.AuditLogs/04.logs_audit_GET_csv.sh" out.csv 2
expect "04 GET: asks for text/csv, the hours, and up to 1000" "${RC}:$(calls):$(has_header 'accept: text/csv')" "0:GET ${A}?duration=2&limit=1000:1"
has "04 GET: how many lines it wrote" "Wrote out.csv: 3 line(s) including the header."
has "04 GET: its header" "Its header: User Name, Remote Host, Date Modified"
STATUS_GET=406 run "27.AuditLogs/04.logs_audit_GET_csv.sh" out.csv
expect "04 GET: a refusal (406) exits 1 and leaves no file" "${RC}:$([ -f "${WORK}/admin/27.AuditLogs/out.csv" ] && echo file || echo none)" "1:none"
run "27.AuditLogs/04.logs_audit_GET_csv.sh" out.csv 0
nothing_sent "04 GET: HOURS must be 1 or more, nothing sent"
GET_BODY=

V="${BASE}/logs/server"
norm() { sed 's/fromDate=[^&]*/fromDate=D/'; }
SERVERS='{"resultSet":{"returnCount":1,"totalCount":44301},"result":[{"time":"Wed, 07 Oct 2026 10:36:18 +0300","level":"INFO","component":"ftpd","message":"[Ftp Default] virtual user example_user logged in from /1.2.3.4:5."}]}'
GET_BODY=$(body servers "${SERVERS}")
run "28.ServerLogs/01.logs_server_GET.sh" 120 "logged in" FTPD,HTTPD INFO,WARN
expect "01 GET: the count since, then the filtered 20, a parameter for each component and level" "${RC}:$(calls | norm)" "0:GET ${V}?fromDate=D&limit=1&fields=id
GET ${V}?fromDate=D&message=logged in&component=FTPD&component=HTTPD&level=INFO&level=WARN&limit=20&fields=time,level,component,message"
has "01 GET: an entry" "  Wed, 07 Oct 2026 10:36:18 +0300  INFO  ftpd  [Ftp Default] virtual user example_user logged in from /1.2.3.4:5."
SINCE_SENT=$(calls | sed -n '1s/.*fromDate=\([^&]*\)&.*/\1/p')
expect "01 GET: fromDate is an RFC 2822 date in GMT" "$(printf '%s' "${SINCE_SENT}" | grep -cE '^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT$')" "1"
AGE=$(python3 -c 'import email.utils, sys, time; print(int(time.time() - email.utils.parsedate_to_datetime(sys.argv[1]).timestamp()))' "${SINCE_SENT}")
expect "01 GET: and it is MINUTES ago" "$(( AGE >= 7195 && AGE <= 7215 ))" "1"
run "28.ServerLogs/01.logs_server_GET.sh"
expect "01 GET: an hour and no filter but the date by default" "$(calls | sed -n '2p' | norm)" "GET ${V}?fromDate=D&limit=20&fields=time,level,component,message"
for ARGS in "0" "60 x NOPE" "60 x FTPD,NOPE" "60 x FTPD LOUD" "60 x FTPD INFO,LOUD" "60 x ftpd"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "28.ServerLogs/01.logs_server_GET.sh" "$@"
    nothing_sent "01 GET: refuses '${ARGS}', nothing sent"
done
GET_BODY=
SERVER_ENTRY='{"time":"Wed, 07 Oct 2026 10:38:40 +0300","level":"INFO","component":"audit","thread":"https-exec-21","message":"admin Admin Session expired.","className":"AuditLogMessage","method":"append","line":56}'
GET_BODY=$(body server_one "${SERVER_ENTRY}")
run "28.ServerLogs/02.logs_server_id_GET.sh" QUJD
expect "02 GET: the id given" "${RC}:$(calls)" "0:GET ${V}/QUJD"
has "02 GET: the summary" "  Wed, 07 Oct 2026 10:38:40 +0300  INFO  audit  thread https-exec-21"
has "02 GET: who wrote it" "  written by AuditLogMessage.append line 56"
GET_BODY=
SEQUENCE=$(sequence server_newest '{"resultSet":{"totalCount":5}}' '{"result":[{"id":{"urlrepresentation":"QUJD"}}]}' "${SERVER_ENTRY}")
run "28.ServerLogs/02.logs_server_id_GET.sh"
expect "02 GET: no id, so the LAST entry is asked for (the log is oldest first), then read" "$(calls)" "GET ${V}?limit=1&fields=id
GET ${V}?limit=1&offset=4&fields=id
GET ${V}/QUJD"
SEQUENCE=
STATUS_GET=400 run "28.ServerLogs/02.logs_server_id_GET.sh" "bad id"
expect "02 GET: a refused id (400) exits 1" "${RC}" "1"
GET_BODY=$(body server_csv 'Time, Level, Component, Message
"10/07/2026 00:05:08.313","INFO","FTPD","hello"')
STATUS=200 STATUS_GET=200 run "28.ServerLogs/03.logs_server_GET_csv.sh" out.csv 30 FTPD
expect "03 GET: asks for text/csv, with the date and the component" "${RC}:$(calls | norm):$(has_header 'accept: text/csv')" "0:GET ${V}?fromDate=D&component=FTPD&limit=1000:1"
has "03 GET: how many lines it wrote" "Wrote out.csv: 2 line(s) including the header."
STATUS=200 STATUS_GET=200 run "28.ServerLogs/03.logs_server_GET_csv.sh" out.csv
expect "03 GET: 60 minutes and no component by default" "$(calls | norm)" "GET ${V}?fromDate=D&limit=1000"
for ARGS in "out.csv 0" "out.csv 5 NOPE"; do
    # shellcheck disable=SC2086
    set -- ${ARGS}
    run "28.ServerLogs/03.logs_server_GET_csv.sh" "$@"
    nothing_sent "03 GET: refuses '${ARGS}', nothing sent"
done
GET_BODY=

echo
echo "=== 29.MailTemplates ==="
F=29.MailTemplates
M="${BASE}/mailTemplates"
MAIL_LIST='{"resultSet":{"returnCount":2,"totalCount":8},"result":[{"name":"AdhocDefault.xhtml","description":"AdHoc Notifications"},{"name":"example.xhtml","description":null}]}'
MAIL_ONE='{"resultSet":{"returnCount":1,"totalCount":8},"result":[{"name":"example_mail.xhtml","description":"Example one"}]}'
MAIL_NONE='{"resultSet":{"returnCount":1,"totalCount":8},"result":[{"name":"example_mail.xhtml","description":null}]}'
forms() { printf '%s\n' "${OUT}" | grep '^FORM:'; }

GET_BODY=$(body mail_list "${MAIL_LIST}")
run "${F}/01.mailTemplates_GET.sh"
expect "01 GET: the count, then every template" "${RC}:$(calls)" "0:GET ${M}?limit=1&fields=name
GET ${M}?limit=100"
has "01 GET: says what it is counting" "Mail templates: "
expect "01 GET: and the total count is on a line of its own (the stub's lines come between)" "$(printf '%s\n' "${OUT}" | grep -cx 8)" "1"
has "01 GET: one line per template, name and description" "  AdhocDefault.xhtml  AdHoc Notifications"
has "01 GET: - for a template with no description" "  example.xhtml  -"
run "${F}/01.mailTemplates_GET.sh" AdhocDefault.xhtml "AdHoc Notifications"
expect "01 GET: the name and the description are sent as exact filters" "$(calls | tail -2)" "GET ${M}?name=AdhocDefault.xhtml
GET ${M}?description=AdHoc Notifications"
GET_BODY=

printf '<html xmlns="http://www.w3.org/1999/xhtml"/>\n' > "${WORK}/files/mail.xhtml"
printf 'plain text\n' > "${WORK}/files/mail.txt"
STATUS=201 LOCATION=example_mail.xhtml run "${F}/02.mailTemplates_POST.sh"
expect "02 POST: POST /mailTemplates" "${RC}:$(calls)" "0:POST ${M}"
expect "02 POST: the name and the default description are form fields" "$(forms | grep -v '^FORM: file=')" "FORM: name=example_mail.xhtml
FORM: description=Created by 29.MailTemplates"
SAMPLE=$(forms | sed -n 's/^FORM: file=@\(.*\);type=application.xhtml+xml;filename=example_mail.xhtml$/\1/p')
expect "02 POST: with no file, the sample it wrote is sent under the template's name" "$([ -n "${SAMPLE}" ] && echo sent)" "sent"
expect "02 POST: and it is removed afterwards" "$([ -e "${SAMPLE}" ] && echo left || echo removed)" "removed"
has "02 POST: prints the end of Location" "Its address ends: example_mail.xhtml"
STATUS=201 run "${F}/02.mailTemplates_POST.sh" "example other.xhtml" "${WORK}/files/mail.txt" "A <b> & @x"
expect "02 POST: a file with any name goes up under the template's name, the description as it is" "$(forms)" "FORM: file=@${WORK}/files/mail.txt;type=application/xhtml+xml;filename=example other.xhtml
FORM: name=example other.xhtml
FORM: description=A <b> & @x"
STATUS=201 run "${F}/02.mailTemplates_POST.sh" example_mail.xhtml "${WORK}/files/mail.xhtml" ""
expect "02 POST: an empty description is sent empty" "$(forms | tail -1)" "FORM: description="
POST_BODY=$(body mail_dup '{"message":"Error validating request","validationErrors":["Template with name example_mail.xhtml already exists."]}')
STATUS=409 run "${F}/02.mailTemplates_POST.sh" example_mail.xhtml "${WORK}/files/mail.xhtml"
expect "02 POST: a 409 exits 1 and says why" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'already exists')" "1:1"
POST_BODY=
run "${F}/02.mailTemplates_POST.sh" "  "
nothing_sent "02 POST: a blank name is refused, nothing sent"
for ARGS in "a/b.xhtml" "../x.xhtml" 'a\b.xhtml' "example_mail.txt" "example_mail" "example_mail.xhtml ${WORK}/files/missing.xhtml"; do
    # shellcheck disable=SC2086
    set -f; set -- ${ARGS}; set +f
    run "${F}/02.mailTemplates_POST.sh" "$@"
    nothing_sent "02 POST: refuses '${ARGS}', nothing sent"
done

STATUS=200 run "${F}/03.mailTemplates_name_HEAD.sh"
expect "03 HEAD: example_mail.xhtml by default" "${RC}:$(calls)" "0:HEAD ${M}/example_mail.xhtml"
has "03 HEAD: says it exists" "The mail template example_mail.xhtml exists."
STATUS=200 run "${F}/03.mailTemplates_name_HEAD.sh" "example mail.xhtml"
expect "03 HEAD: a name with a space is URL-encoded in the path" "$(calls)" "HEAD ${M}/example%20mail.xhtml"
STATUS=404 run "${F}/03.mailTemplates_name_HEAD.sh"
expect "03 HEAD: 404 is 'does not exist', exit 1" "${RC}" "1"
run "${F}/03.mailTemplates_name_HEAD.sh" "a/b.xhtml"
nothing_sent "03 HEAD: a name with a / is refused, nothing sent"

GET_BODY=$(body mail_one "${MAIL_ONE}")
STATUS=200 STATUS_GET=200 run "${F}/04.mailTemplates_name_GET.sh" example_mail.xhtml saved.xhtml
expect "04 GET: the description from the list, then the file" "${RC}:$(calls)" "0:GET ${M}?name=example_mail.xhtml&fields=description
GET ${M}/example_mail.xhtml"
expect "04 GET: the file is asked for as application/xhtml+xml" "$(has_header 'accept: application/xhtml+xml')" "1"
has "04 GET: says it is the description" "Description: "
expect "04 GET: and the description is on a line of its own" "$(printf '%s\n' "${OUT}" | grep -cx 'Example one')" "1"
has "04 GET: says where the file went" "Written to saved.xhtml,"
expect "04 GET: and it is there" "$([ -f "${WORK}/admin/${F}/saved.xhtml" ] && echo file)" "file"
STATUS=404 STATUS_GET=404 run "${F}/04.mailTemplates_name_GET.sh" example_mail.xhtml gone.xhtml
expect "04 GET: a 404 exits 1 and leaves no file" "${RC}:$([ -e "${WORK}/admin/${F}/gone.xhtml" ] && echo file || echo none)" "1:none"
run "${F}/04.mailTemplates_name_GET.sh" "a/b.xhtml"
nothing_sent "04 GET: a name with a / is refused, nothing sent"
GET_BODY=

GET_BODY=$(body mail_one "${MAIL_ONE}")
STATUS=204 run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/mail.xhtml"
expect "05 PUT: looks the template up, reads its description, then PUTs" "${RC}:$(calls)" "0:HEAD ${M}/example_mail.xhtml
GET ${M}?name=example_mail.xhtml&fields=description
PUT ${M}/example_mail.xhtml"
expect "05 PUT: the file under the template's name, and the description it had" "$(forms)" "FORM: file=@${WORK}/files/mail.xhtml;type=application/xhtml+xml;filename=example_mail.xhtml
FORM: description=Example one"
GET_BODY=$(body mail_none "${MAIL_NONE}")
STATUS=204 run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/mail.xhtml"
expect "05 PUT: a template with no description is sent with an empty one" "$(forms | tail -1)" "FORM: description="
GET_BODY=
STATUS=204 run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/mail.xhtml" "New text"
expect "05 PUT: a description given is used, and not looked up" "$(calls):$(forms | tail -1)" "HEAD ${M}/example_mail.xhtml
PUT ${M}/example_mail.xhtml:FORM: description=New text"
STATUS=204 run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/mail.xhtml" ""
expect "05 PUT: an empty description clears it" "$(forms | tail -1)" "FORM: description="
STATUS=404 run "${F}/05.mailTemplates_name_PUT.sh" example_nope.xhtml "${WORK}/files/mail.xhtml"
expect "05 PUT: a template that is not there is not created (PUT would): exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
STATUS=400 run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/mail.xhtml" "x"
expect "05 PUT: a refusal exits 1" "${RC}" "1"
run "${F}/05.mailTemplates_name_PUT.sh" example_mail.xhtml "${WORK}/files/missing.xhtml"
nothing_sent "05 PUT: no such file, nothing sent"
run "${F}/05.mailTemplates_name_PUT.sh"
nothing_sent "05 PUT: no arguments, nothing sent"
run "${F}/05.mailTemplates_name_PUT.sh" "a/b.xhtml" "${WORK}/files/mail.xhtml"
nothing_sent "05 PUT: a name with a / is refused, nothing sent"

STATUS=204 run "${F}/06.mailTemplates_name_DELETE.sh" "example mail.xhtml"
expect "06 DELETE: the name URL-encoded in the path" "${RC}:$(calls)" "0:DELETE ${M}/example%20mail.xhtml"
has "06 DELETE: prints the code" "HTTP 204"
STATUS=404 run "${F}/06.mailTemplates_name_DELETE.sh" example_nope.xhtml
expect "06 DELETE: a refused delete exits 1" "${RC}" "1"
run "${F}/06.mailTemplates_name_DELETE.sh"
nothing_sent "06 DELETE: no name, nothing sent"
run "${F}/06.mailTemplates_name_DELETE.sh" "a\\b.xhtml"
nothing_sent "06 DELETE: a name with a backslash is refused, nothing sent"

echo
echo "=== 09.CompositeRoutes (08 to 10: the routes operations not called before) ==="
F=09.CompositeRoutes
R="${BASE}/routes"
ONE_ROUTE='{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"id":"r1id","name":"example_route"}]}'
# the name filter takes a *, so a longer name comes back too: only the exact one counts
LONGER='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"id":"r1id","name":"example_route"},{"id":"r2id","name":"example_route2"}]}'
TWO_SAME='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"id":"r1id","name":"example_route"},{"id":"r2id","name":"example_route"}]}'
NO_ROUTE='{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}'
ROUTE_FULL='{"id":"r1id","name":"example_route","description":"old text","type":"SIMPLE","conditionType":"ALWAYS","condition":"true","steps":[{"id":"s1","type":"Compress","status":"ENABLED","metadata":{"links":{"route":"x"}}},{"id":"s2","type":"SendToPartner","status":"ENABLED"}],"metadata":{"links":{"self":"y"}}}'

GET_BODY=$(body route_one "${ONE_ROUTE}")
run "${F}/08.routes_id_HEAD.sh" example_route
expect "08 HEAD: looks the id up by name, then HEADs the id" "${RC}:$(calls)" "0:GET ${R}?name=example_route&fields=id,name
HEAD ${R}/r1id"
has "08 HEAD: says the route exists, with its id" "The route example_route exists, id r1id."
run "${F}/08.routes_id_HEAD.sh"
expect "08 HEAD: SimpleRoute_Compress by default" "$(calls | head -1)" "GET ${R}?name=SimpleRoute_Compress&fields=id,name"
STATUS=404 run "${F}/08.routes_id_HEAD.sh" example_route
expect "08 HEAD: 404 is 'does not exist', exit 1" "${RC}" "1"
GET_BODY=$(body route_longer "${LONGER}")
run "${F}/08.routes_id_HEAD.sh" example_route
expect "08 HEAD: a longer name matched by the filter is not counted" "${RC}:$(calls | tail -1)" "0:HEAD ${R}/r1id"
GET_BODY=$(body route_same "${TWO_SAME}")
run "${F}/08.routes_id_HEAD.sh" example_route
expect "08 HEAD: two routes of one name, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
GET_BODY=$(body route_none "${NO_ROUTE}")
run "${F}/08.routes_id_HEAD.sh" example_route
expect "08 HEAD: no such route, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
run "${F}/08.routes_id_HEAD.sh" "example route"
expect "08 HEAD: a name with a space goes into the query for curl to encode" "$(calls)" "GET ${R}?name=example route&fields=id,name"

SEQUENCE=$(sequence put_ok "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/09.routes_id_PUT.sh" example_route "new text"
expect "09 PUT: looks the id up, reads the route, PUTs it" "${RC}:$(calls)" "0:GET ${R}?name=example_route&fields=id,name
GET ${R}/r1id
PUT ${R}/r1id"
expect "09 PUT: sends the whole route, steps included, only description changed, metadata dropped" \
  "$(payload 1 | jq -c .)" \
  '{"id":"r1id","name":"example_route","description":"new text","type":"SIMPLE","conditionType":"ALWAYS","condition":"true","steps":[{"id":"s1","type":"Compress","status":"ENABLED","metadata":{"links":{"route":"x"}}},{"id":"s2","type":"SendToPartner","status":"ENABLED"}]}'
has "09 PUT: prints the description before" "The description of example_route is now: old text"
has "09 PUT: prints the code" "HTTP 204"
SEQUENCE=$(sequence put_default "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/09.routes_id_PUT.sh" example_route
expect "09 PUT: a default description" "$(payload 1 | jq -r .description)" "Changed by 09.routes_id_PUT.sh"
SEQUENCE=$(sequence put_quote "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/09.routes_id_PUT.sh" example_route 'say "hi" \ done'
expect "09 PUT: quotes and a backslash stay valid JSON" "$(payload 1 | jq -r .description)" 'say "hi" \ done'
SEQUENCE=$(sequence put_refused "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=400 run "${F}/09.routes_id_PUT.sh" example_route x
expect "09 PUT: a refusal exits 1" "${RC}" "1"
SEQUENCE=
GET_BODY=$(body route_none "${NO_ROUTE}")
run "${F}/09.routes_id_PUT.sh" example_route x
expect "09 PUT: no such route, exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
run "${F}/09.routes_id_PUT.sh"
expect "09 PUT: no name, exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"

SEQUENCE=$(sequence patch_ok "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/10.routes_id_PATCH.sh" example_route SendToPartner
expect "10 PATCH: looks the id up, reads the route, PATCHes it" "${RC}:$(calls)" "0:GET ${R}?name=example_route&fields=id,name
GET ${R}/r1id
PATCH ${R}/r1id"
expect "10 PATCH: disables the step found at its position (1), nothing else" "$(payload 1 | jq -c .)" \
  '[{"op":"replace","path":"/steps/1/status","value":"DISABLED"}]'
has "10 PATCH: prints the position and the status before" "The SendToPartner step of example_route is at position 1, and is ENABLED."
has "10 PATCH: prints the code" "HTTP 204"
SEQUENCE=$(sequence patch_first "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/10.routes_id_PATCH.sh" example_route Compress ENABLED
expect "10 PATCH: the first step is position 0, and a status can be given" "$(payload 1 | jq -c .)" \
  '[{"op":"replace","path":"/steps/0/status","value":"ENABLED"}]'
SEQUENCE=$(sequence patch_nostep "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=204 run "${F}/10.routes_id_PATCH.sh" example_route Rename
expect "10 PATCH: no step of that type, exit 1, no PATCH" "${RC}:$(calls | grep -c PATCH)" "1:0"
SEQUENCE=$(sequence patch_refused "${ONE_ROUTE}" "${ROUTE_FULL}")
STATUS=400 run "${F}/10.routes_id_PATCH.sh" example_route Compress
expect "10 PATCH: a refusal exits 1" "${RC}" "1"
SEQUENCE=
for args in "" "example_route" "example_route Compress enabled" "example_route Compress MAYBE"; do
    # shellcheck disable=SC2086
    run "${F}/10.routes_id_PATCH.sh" ${args}
    expect "10 PATCH: bad arguments (${args:-none}), exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
GET_BODY=

echo
echo "=== 30.RouteStepsMetadata ==="
F=30.RouteStepsMetadata
STEPS='[{"stepType":"Compress","stepCategory":"Transformation","stepDisplayName":"Compress","endpointSchema":"st.compress","stepJarName":"compress-route"},{"stepType":"setflowattributes","stepCategory":"Transformation","stepDisplayName":"Set Flow Attributes","endpointSchema":"st.setflowattributes","stepJarName":"axway-step-setflowattributes"},{"stepType":"SendToPartner","stepCategory":"Routing","stepDisplayName":"Send To Partner","endpointSchema":"st.sendtopartnersite","stepJarName":"sendtopartner-route"},{"stepType":"NoTableType","stepCategory":"Routing","stepDisplayName":"Not In The Table","endpointSchema":"st.x","stepJarName":"x"}]'
GET_BODY=$(body route_steps "${STEPS}")
run "${F}/01.routeStepsMetadata_GET.sh"
expect "01 GET: one call, GET /routeStepsMetadata" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsMetadata"
has "01 GET: counts the step types (a plain array)" "Route step types: 4"
has "01 GET: one line per type, category, type, display name" "  Transformation  Compress  Compress"
has "01 GET: a type written in lower case is shown as it is" "  Transformation  setflowattributes  Set Flow Attributes"
has "01 GET: a routing type" "  Routing  SendToPartner  Send To Partner"
run "${F}/01.routeStepsMetadata_GET.sh" Compress
expect "01 GET: a step type given is read from the same one call" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsMetadata"
has "01 GET: shows everything about that type" '  "endpointSchema": "st.compress",'
expect "01 GET: and nothing about the others" "$(printf '%s\n' "${OUT}" | grep -c 'SendToPartner')" "0"
run "${F}/01.routeStepsMetadata_GET.sh" Compress minimal
expect "01 GET minimal: still one call, GET /routeStepsMetadata" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsMetadata"
expect "01 GET minimal: no heading, only the JSON" "$(printf '%s\n' "${OUT}" | grep -c 'Step type')" "0"
expect "01 GET minimal: Compress is type, status, actionOnStepFailure, filter, compressionType, compressionLevel" \
    "$(printf '%s\n' "${OUT}" | sed -n '/^{$/,/^}$/p' | jq -c 'keys_unsorted')" '["type","status","actionOnStepFailure","fileFilterExpression","fileFilterExpressionType","compressionType","compressionLevel"]'
expect "01 GET minimal: the step is of the type asked" "$(printf '%s\n' "${OUT}" | sed -n '/^{$/,/^}$/p' | jq -r '.type + " " + .status + " " + .actionOnStepFailure')" "Compress ENABLED FAIL"
run "${F}/01.routeStepsMetadata_GET.sh" SendToPartner minimal
expect "01 GET minimal: SendToPartner names a site with the #!#CVD#!# suffix" "$(printf '%s\n' "${OUT}" | sed -n '/^{$/,/^}$/p' | jq -r '.transferSiteExpression, .transferSiteExpressionType')" "$(printf 'partner_site#!#CVD#!#\nLIST')"
run "${F}/01.routeStepsMetadata_GET.sh" setflowattributes minimal
expect "01 GET minimal: setflowattributes needs nothing beyond the three" "$(printf '%s\n' "${OUT}" | sed -n '/^{$/,/^}$/p' | jq -c 'keys_unsorted')" '["type","status","actionOnStepFailure"]'
run "${F}/01.routeStepsMetadata_GET.sh" NoTableType minimal
expect "01 GET minimal: a listed type with no table entry, exit 1" "${RC}" "1"
has "01 GET minimal: says no minimal step is kept" "keeps no minimal step for NoTableType"
run "${F}/01.routeStepsMetadata_GET.sh" Nope minimal
expect "01 GET minimal: a type the server does not list, exit 1" "${RC}" "1"
has "01 GET minimal: says so" "Not a step type of this server"
run "${F}/01.routeStepsMetadata_GET.sh" compress
expect "01 GET: the step type is case sensitive: no match, exit 1" "${RC}" "1"
run "${F}/01.routeStepsMetadata_GET.sh" Nope
expect "01 GET: an unknown step type, exit 1" "${RC}" "1"
has "01 GET: says so" "Not a step type of this server"
STATUS=403 run "${F}/01.routeStepsMetadata_GET.sh"
expect "01 GET: a refusal exits 1" "${RC}" "1"
has "01 GET: and prints the code" "HTTP 403"
GET_BODY=

echo
echo "=== 31.RouteStepsCharsets ==="
F=31.RouteStepsCharsets
CHARSETS='{"charsets":["Big5","IBM037","ISO-8859-1","US-ASCII","UTF-16","UTF-8","windows-1252"]}'
GET_BODY=$(body charsets "${CHARSETS}")
run "${F}/01.routeStepsCharsets_GET.sh"
expect "01 GET: one call, GET /routeStepsCharsets" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsCharsets"
has "01 GET: counts the charsets (in an object, not an array)" "Character sets: 7"
has "01 GET: one name per line" "  Big5"
has "01 GET: a name with a hyphen and lower case letters is shown as it is" "  windows-1252"
run "${F}/01.routeStepsCharsets_GET.sh" UTF-8
expect "01 GET: a name given is looked up in the one answer" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsCharsets"
has "01 GET: a listed name" "UTF-8 is in the list."
run "${F}/01.routeStepsCharsets_GET.sh" utf-8
expect "01 GET: a name that differs only in case is not listed as written, exit 1" "${RC}" "1"
has "01 GET: and the listed spelling is shown" "utf-8 is not in the list as written; the list has UTF-8."
run "${F}/01.routeStepsCharsets_GET.sh" NOPE-9
expect "01 GET: a name that is not listed, exit 1" "${RC}" "1"
has "01 GET: says so" "NOPE-9 is not in the list."

printf '%s\n' '{"name":"example_route","steps":[{"type":"Compress"},{"type":"EncodingConversion","inputCharset":"UTF-8","outputCharset":"UTF-16"},{"type":"LineEnding","inputCharset":"IBM037"}]}' > "${WORK}/files/route_ok.json"
run "${F}/01.routeStepsCharsets_GET.sh" step "${WORK}/files/route_ok.json"
expect "01 GET step: a route's steps, one call, exit 0" "${RC}:$(calls)" "0:GET ${BASE}/routeStepsCharsets"
has "01 GET step: the input charset of a step, by its position and type" "  step 1 EncodingConversion inputCharset UTF-8: listed"
has "01 GET step: the output charset" "  step 1 EncodingConversion outputCharset UTF-16: listed"
has "01 GET step: a later step" "  step 2 LineEnding inputCharset IBM037: listed"
expect "01 GET step: a step with no charset has no line" "$(printf '%s\n' "${OUT}" | grep -c 'Compress')" "0"
printf '%s\n' '[{"type":"EncodingConversion","inputCharset":"UTF-8","outputCharset":"UTF8"}]' > "${WORK}/files/steps_bad.json"
run "${F}/01.routeStepsCharsets_GET.sh" step "${WORK}/files/steps_bad.json"
expect "01 GET step: a charset that is not listed, exit 1" "${RC}" "1"
has "01 GET step: is marked" "  step 0 EncodingConversion outputCharset UTF8: NOT listed"
printf '%s\n' '{"type":"Rename","outputFileName":"a.txt"}' > "${WORK}/files/step_none.json"
run "${F}/01.routeStepsCharsets_GET.sh" step "${WORK}/files/step_none.json"
expect "01 GET step: a single step with no charset, exit 0" "${RC}" "0"
has "01 GET step: says nothing was to check" "nothing to check"
printf '%s\n' '{"type":"LinePadding","inputCharset":"UTF-8"}' > "${WORK}/files/step_one.json"
run "${F}/01.routeStepsCharsets_GET.sh" step "${WORK}/files/step_one.json"
has "01 GET step: a single step object" "  step 0 LinePadding inputCharset UTF-8: listed"
printf 'not json\n' > "${WORK}/files/not_json.txt"
for args in "step" "step ${WORK}/files/missing.json" "step ${WORK}/files/not_json.txt" "UTF-8 extra" "step ${WORK}/files/step_one.json extra"; do
    run "${F}/01.routeStepsCharsets_GET.sh" ${args}
    expect "01 GET: bad arguments '${args##*/}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
STATUS=403 run "${F}/01.routeStepsCharsets_GET.sh"
expect "01 GET: a refusal exits 1" "${RC}" "1"
has "01 GET: and prints the code" "HTTP 403"
GET_BODY=

echo
echo "=== 32.Sessions ==="
F=32.Sessions
U="${BASE}/sessions"
SESSIONS='[{"id":"FTP:aa11:24539","userName":"example_user","host":"client.example.com","protocol":"FTP","userClass":"VirtClass","currentTransferBandwidth":"-1","command":"IDLE","sessionCreationTime":"Wed, 7 Oct 2026 19:17:06 +0300","nodeIp":"Local \n (node.example.com)","serverName":"Ftp Default"},{"id":"HTTP:bb22","userName":"example_user","host":"client.example.com","protocol":"HTTP","userClass":"VirtClass","currentTransferBandwidth":"-1","command":"","sessionCreationTime":"Wed, 7 Oct 2026 19:17:07 +0300","nodeIp":"Local","serverName":"Http Default"},{"id":"SSH:cc33","userName":"example_other","host":"other.example.com","protocol":"SSH","userClass":"VirtClass","currentTransferBandwidth":"-1","command":"","sessionCreationTime":"Wed, 7 Oct 2026 19:18:00 +0300","nodeIp":"Local","serverName":"Ssh Default"}]'
GET_BODY=$(body sessions "${SESSIONS}")
run "${F}/01.sessions_GET.sh"
expect "01 GET: one call, GET /sessions, no type sent" "${RC}:$(calls)" "0:GET ${U}"
has "01 GET: counts the sessions (a plain array)" "Sessions: 3"
has "01 GET: an FTP session, with its command" "  FTP:aa11:24539  example_user  FTP  client.example.com  IDLE  Wed, 7 Oct 2026 19:17:06 +0300"
has "01 GET: an empty command is shown as -" "  HTTP:bb22  example_user  HTTP  client.example.com  -  Wed, 7 Oct 2026 19:17:07 +0300"
run "${F}/01.sessions_GET.sh" SSH
expect "01 GET SSH: sends type=SSH" "${RC}:$(calls)" "0:GET ${U}?type=SSH"
has "01 GET SSH: and keeps only the SSH ones itself, since the server ignores type" "Sessions: 1"
expect "01 GET SSH: no FTP line" "$(printf '%s\n' "${OUT}" | grep -c 'FTP:')" "0"
run "${F}/01.sessions_GET.sh" all example_user
has "01 GET USER: only that user's sessions" "Sessions: 2"
expect "01 GET USER: the other user's session is left out" "$(printf '%s\n' "${OUT}" | grep -c 'example_other')" "0"
run "${F}/01.sessions_GET.sh" FTP nobody
has "01 GET: no match is an empty list, exit 0" "Sessions: 0"
GET_BODY=$(body no_sessions '[]')
run "${F}/01.sessions_GET.sh"
expect "01 GET: no session open, exit 0" "${RC}" "0"
has "01 GET: says 0" "Sessions: 0"
for args in "ftp" "XYZ" "FTP a b"; do
    run "${F}/01.sessions_GET.sh" ${args}
    expect "01 GET: bad arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
STATUS=403 run "${F}/01.sessions_GET.sh"
expect "01 GET: a refusal exits 1" "${RC}" "1"
has "01 GET: and prints the code" "HTTP 403"

ONE='{"id":"FTP:aa11:24539","userName":"example_user","host":"client.example.com","protocol":"FTP","userClass":"VirtClass","currentTransferBandwidth":"-1","command":"STOR","sessionCreationTime":"Wed, 7 Oct 2026 19:17:06 +0300","nodeIp":"Local","serverName":"Ftp Default"}'
GET_BODY=$(body one_session "${ONE}")
run "${F}/02.sessions_id_GET.sh" "FTP:aa11:24539"
expect "02 GET: one call, the id URL-encoded once" "${RC}:$(calls)" "0:GET ${U}/FTP%3Aaa11%3A24539"
has "02 GET: the summary" "  FTP session of example_user from client.example.com, on Ftp Default"
has "02 GET: the command and the start" "  command STOR, since Wed, 7 Oct 2026 19:17:06 +0300"
GET_BODY=$(body sessions "${SESSIONS}")
SEQUENCE=$(sequence first_session '[{"id":"FTP:aa11:24539"}]' "${ONE}")
GET_BODY= run "${F}/02.sessions_id_GET.sh"
expect "02 GET: with no id it asks for the first session, then reads it" "${RC}:$(calls)" "0:GET ${U}?limit=1&fields=id
GET ${U}/FTP%3Aaa11%3A24539"
SEQUENCE=
GET_BODY=$(body no_sessions '[]')
run "${F}/02.sessions_id_GET.sh"
expect "02 GET: with no id and no session, exit 1 after one call" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
has "02 GET: says so" "There are no sessions to read."
GET_BODY=$(body not_found '{"message":"Error validating request","validationErrors":["Session with id HTTP:zz was not found."]}')
STATUS_GET=404 run "${F}/02.sessions_id_GET.sh" "HTTP:zz"
expect "02 GET: a session that is gone, exit 1" "${RC}" "1"
has "02 GET: prints the server's reason" "Session with id HTTP:zz was not found."
run "${F}/02.sessions_id_GET.sh" a b
expect "02 GET: two arguments exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
STATUS_GET=

GET_BODY=$(body one_session "${ONE}")
STATUS=204 STATUS_GET=200 run "${F}/03.sessions_id_DELETE.sh" "FTP:aa11:24539" example_user
expect "03 DELETE: reads the session, then deletes that id" "${RC}:$(calls)" "0:GET ${U}/FTP%3Aaa11%3A24539
DELETE ${U}/FTP%3Aaa11%3A24539"
has "03 DELETE: says whose session it ends" "Ending the FTP session of example_user..."
has "03 DELETE: prints the code" "HTTP 204"
STATUS=204 STATUS_GET=200 run "${F}/03.sessions_id_DELETE.sh" "FTP:aa11:24539"
expect "03 DELETE: with no user given it still ends the session" "${RC}:$(calls | tail -1)" "0:DELETE ${U}/FTP%3Aaa11%3A24539"
STATUS=204 STATUS_GET=200 run "${F}/03.sessions_id_DELETE.sh" "FTP:aa11:24539" someone_else
expect "03 DELETE: another user's session is NOT ended, exit 1, only the read was sent" "${RC}:$(calls)" "1:GET ${U}/FTP%3Aaa11%3A24539"
has "03 DELETE: says nothing was ended" "That is a FTP session of example_user, not of someone_else: nothing was ended."
GET_BODY=$(body not_found '{"message":"Error validating request","validationErrors":["Session with id HTTP:zz was not found."]}')
STATUS=204 STATUS_GET=404 run "${F}/03.sessions_id_DELETE.sh" "HTTP:zz"
expect "03 DELETE: a session that is gone is not deleted, exit 1" "${RC}:$(calls | grep -c DELETE)" "1:0"
GET_BODY=$(body one_session "${ONE}")
GET_BODY=$(body gone '{"message":"Error validating request","validationErrors":["Session with id FTP:aa11:24539 not found"]}')
STATUS=404 STATUS_GET=200 run "${F}/03.sessions_id_DELETE.sh" "FTP:aa11:24539"
expect "03 DELETE: a refusal of the delete exits 1" "${RC}" "1"
has "03 DELETE: prints the code and the reason" "HTTP 404"
for args in "" "nocolon" "FTP:a user x" ; do
    run "${F}/03.sessions_id_DELETE.sh" ${args}
    expect "03 DELETE: bad arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

BANDWIDTH='[{"loginName":"example_user","bandwidthUsageStats":{"inbound":100,"outbound":0},"sessions":{"total":2,"http":0,"ftp":2,"ssh":0},"maxAllowedBandwidth":{"inbound":500,"outbound":600}},{"loginName":"example_other","bandwidthUsageStats":{"inbound":0,"outbound":7},"sessions":{"total":1,"http":1,"ftp":0,"ssh":0}}]'
GET_BODY=$(body bandwidth "${BANDWIDTH}")
run "${F}/04.sessions_statistics_bandwidth_GET.sh"
expect "04 GET: one call" "${RC}:$(calls)" "0:GET ${U}/statistics/bandwidth"
has "04 GET: counts the login names" "Login names using bandwidth: 2"
has "04 GET: a login name with its sessions, rates and limit" "  example_user  2 sessions (ftp 2, http 0, ssh 0)  in 100, out 0  max in 500, out 600"
has "04 GET: no limit set shows -" "  example_other  1 sessions (ftp 0, http 1, ssh 0)  in 0, out 7  max in -, out -"
run "${F}/04.sessions_statistics_bandwidth_GET.sh" 5
expect "04 GET: a limit goes into the query" "${RC}:$(calls)" "0:GET ${U}/statistics/bandwidth?limit=5"
GET_BODY=$(body no_bandwidth '[]')
run "${F}/04.sessions_statistics_bandwidth_GET.sh"
has "04 GET: an empty answer is 0 login names" "Login names using bandwidth: 0"
for args in "0" "-1" "abc" "5 6"; do
    run "${F}/04.sessions_statistics_bandwidth_GET.sh" ${args}
    expect "04 GET: bad arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
STATUS=403 run "${F}/04.sessions_statistics_bandwidth_GET.sh"
expect "04 GET: a refusal exits 1" "${RC}" "1"

USER_CLASSES='[{"userClass":"VirtClass","maxAllowed":"unlimited","instantaneousFTPBandwidth":"N/A","bandwidthUsageStats":{"inbound":0,"outbound":0},"globalLoggedInCounters":{"total":3,"http":1,"ftp":1,"ssh":1},"localLoggedInCounters":{"total":2,"http":1,"ftp":1,"ssh":0}},{"userClass":"RealClass","maxAllowed":"unlimited","instantaneousFTPBandwidth":"N/A","bandwidthUsageStats":{"inbound":0,"outbound":0},"globalLoggedInCounters":{"total":0,"http":0,"ftp":0,"ssh":0},"localLoggedInCounters":{"total":0,"http":0,"ftp":0,"ssh":0}}]'
GET_BODY=$(body user_classes "${USER_CLASSES}")
run "${F}/05.sessions_statistics_userClass_GET.sh"
expect "05 GET: one call" "${RC}:$(calls)" "0:GET ${U}/statistics/userClass"
has "05 GET: counts the classes" "Sessions by user class: 2 classes"
has "05 GET: a class with the sessions on the server and on this node" "  VirtClass  3 sessions (ftp 1, http 1, ssh 1)  here 2  in 0, out 0  max unlimited"
has "05 GET: a class with none" "  RealClass  0 sessions (ftp 0, http 0, ssh 0)  here 0  in 0, out 0  max unlimited"
STATUS=403 run "${F}/05.sessions_statistics_userClass_GET.sh"
expect "05 GET: a refusal exits 1" "${RC}" "1"
GET_BODY=

echo
echo "=== 06.TransferSites (05 to 11: the sites operations not called before) ==="
F=06.TransferSites
S="${BASE}/sites"
LOOK="${S}?account=example_acct&name=example_site&fields=id,name"
ONE_SITE='{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"id":"s1id","name":"example_site"}]}'
# the name filter ignores case and takes a *, so other sites come back too: only the exact name counts
LONGER_SITE='{"resultSet":{"returnCount":3,"totalCount":3},"result":[{"id":"s2id","name":"EXAMPLE_SITE"},{"id":"s1id","name":"example_site"},{"id":"s3id","name":"example_site2"}]}'
TWO_SAME_SITE='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"id":"s1id","name":"example_site"},{"id":"s4id","name":"example_site"}]}'
NO_SITE='{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}'
SITE_FULL='{"type":"ssh","id":"s1id","name":"example_site","account":"example_acct","protocol":"ssh","transferType":"partner","maxConcurrentConnection":4,"default":false,"accessLevel":"PRIVATE","host":"partner.example.com","port":"8022","downloadFolder":"/in","downloadPattern":"*","uploadFolder":"/out","userName":"example_partner","usePassword":true,"password":"{AES128}abcDEF==","postTransmissionActions":{"doAsIn":"${stenv.target}_IN","doAsOut":null},"additionalAttributes":{},"metadata":{"links":{"account":"https://st.example.com:8444/api/v2.0/accounts/example_acct"}}}'
NO_FOLDER_SITE='{"type":"pesit","id":"s1id","name":"example_site","account":"example_acct","protocol":"pesit","host":"partner.example.com","port":"17617","maxConcurrentConnection":0,"metadata":{"links":{}}}'
TEST_OK='{"connectionStatus":"success","authenticationStatus":"success","fingerprintVerificationStatus":"not verified","errorDetails":null}'
TEST_BAD_PW='{"connectionStatus":"success","authenticationStatus":"failed","errorDetails":"Password authentication failed."}'
TEST_REFUSED='{"connectionStatus":"failed","authenticationStatus":"failed","errorDetails":"Connection refused"}'

GET_BODY=$(body site_one "${ONE_SITE}")
run "${F}/05.sites_id_HEAD.sh" example_acct example_site
expect "05 HEAD: looks the id up by account and name, then HEADs the id" "${RC}:$(calls)" "0:GET ${LOOK}
HEAD ${S}/s1id"
has "05 HEAD: says the site exists, with its id" "The site example_site of example_acct exists, id s1id."
run "${F}/05.sites_id_HEAD.sh"
expect "05 HEAD: SSH_PULL of john by default" "$(calls | head -1)" "GET ${S}?account=john&name=SSH_PULL&fields=id,name"
STATUS=404 run "${F}/05.sites_id_HEAD.sh" example_acct example_site
expect "05 HEAD: 404 is 'does not exist', exit 1" "${RC}" "1"
GET_BODY=$(body site_longer "${LONGER_SITE}")
run "${F}/05.sites_id_HEAD.sh" example_acct example_site
expect "05 HEAD: other names the filter matched are not counted, the exact one is used" "${RC}:$(calls | tail -1)" "0:HEAD ${S}/s1id"
GET_BODY=$(body site_same "${TWO_SAME_SITE}")
run "${F}/05.sites_id_HEAD.sh" example_acct example_site
expect "05 HEAD: two sites of one name, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
GET_BODY=$(body site_none "${NO_SITE}")
run "${F}/05.sites_id_HEAD.sh" example_acct example_site
expect "05 HEAD: no such site, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
run "${F}/05.sites_id_HEAD.sh" example_acct "example site"
expect "05 HEAD: a name with a space goes into the query for curl to encode" "$(calls)" "GET ${S}?account=example_acct&name=example site&fields=id,name"

SEQUENCE=$(sequence site_get "${ONE_SITE}" "${SITE_FULL}" "${SITE_FULL}")
run "${F}/06.sites_id_GET.sh" example_acct example_site
expect "06 GET: looks the id up, reads the site, then reads only some fields" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/s1id
GET ${S}/s1id?fields=name,host,port"
has "06 GET: the type" "  type:             ssh"
has "06 GET: the partner" "  partner:          partner.example.com:8022"
has "06 GET: the folders" "  download folder:  /in"
has "06 GET: the upload folder" "  upload folder:    /out"
has "06 GET: the connection limit" "  max connections:  4"
has "06 GET: the password as stored, never in clear" "  password:         {AES128}abcDEF=="
SEQUENCE=$(sequence site_get_none "${ONE_SITE}" "${NO_FOLDER_SITE}")
run "${F}/06.sites_id_GET.sh" example_acct example_site
has "06 GET: a field the type has not is shown as -" "  download folder:  -"
SEQUENCE=$(sequence site_get_unknown "${ONE_SITE}" '{"message":"Error validating request","validationErrors":["Site with id s1id not found or not accessible."]}')
run "${F}/06.sites_id_GET.sh" example_acct example_site
expect "06 GET: an answer with no id, exit 1" "${RC}" "1"
SEQUENCE=

SEQUENCE=$(sequence site_put "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/07.sites_id_PUT.sh" example_acct example_site 9
expect "07 PUT: looks the id up, reads the site, PUTs it" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/s1id
PUT ${S}/s1id"
expect "07 PUT: sends the whole site back, the password as read, only the limit changed, metadata dropped" \
  "$(payload 1 | jq -c .)" \
  '{"type":"ssh","id":"s1id","name":"example_site","account":"example_acct","protocol":"ssh","transferType":"partner","maxConcurrentConnection":9,"default":false,"accessLevel":"PRIVATE","host":"partner.example.com","port":"8022","downloadFolder":"/in","downloadPattern":"*","uploadFolder":"/out","userName":"example_partner","usePassword":true,"password":"{AES128}abcDEF==","postTransmissionActions":{"doAsIn":"${stenv.target}_IN","doAsOut":null},"additionalAttributes":{}}'
has "07 PUT: prints the value before" "maxConcurrentConnection of example_site is now 4."
has "07 PUT: prints the code" "HTTP 204"
SEQUENCE=$(sequence site_put_default "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/07.sites_id_PUT.sh" example_acct example_site
expect "07 PUT: 2 by default" "$(payload 1 | jq -r .maxConcurrentConnection)" "2"
SEQUENCE=$(sequence site_put_zero "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/07.sites_id_PUT.sh" example_acct example_site 0
expect "07 PUT: 0, no limit, is a value (a number, not a string)" "$(payload 1 | jq -c .maxConcurrentConnection)" "0"
SEQUENCE=$(sequence site_put_refused "${ONE_SITE}" "${SITE_FULL}")
STATUS=400 run "${F}/07.sites_id_PUT.sh" example_acct example_site 3
expect "07 PUT: a refusal exits 1" "${RC}" "1"
SEQUENCE=
GET_BODY=$(body site_none "${NO_SITE}")
run "${F}/07.sites_id_PUT.sh" example_acct example_site 3
expect "07 PUT: no such site, exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY=
for args in "" "example_acct" "example_acct example_site abc" "example_acct example_site -1" "example_acct example_site 65536"; do
    # shellcheck disable=SC2086
    run "${F}/07.sites_id_PUT.sh" ${args}
    expect "07 PUT: bad arguments (${args:-none}), exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

SEQUENCE=$(sequence site_patch "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/08.sites_id_PATCH.sh" example_acct example_site /archive
expect "08 PATCH: looks the id up, reads the site, PATCHes it" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/s1id
PATCH ${S}/s1id"
expect "08 PATCH: replaces the download folder, nothing else" "$(payload 1 | jq -c .)" \
  '[{"op":"replace","path":"/downloadFolder","value":"/archive"}]'
has "08 PATCH: prints the folder before" "The download folder of example_site is now /in."
has "08 PATCH: prints the code" "HTTP 204"
SEQUENCE=$(sequence site_patch_default "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/08.sites_id_PATCH.sh" example_acct example_site
expect "08 PATCH: /inbox by default" "$(payload 1 | jq -r '.[0].value')" "/inbox"
SEQUENCE=$(sequence site_patch_quote "${ONE_SITE}" "${SITE_FULL}")
STATUS=204 run "${F}/08.sites_id_PATCH.sh" example_acct example_site 'a "b" \ c'
expect "08 PATCH: quotes and a backslash stay valid JSON" "$(payload 1 | jq -r '.[0].value')" 'a "b" \ c'
SEQUENCE=$(sequence site_patch_nofolder "${ONE_SITE}" "${NO_FOLDER_SITE}")
STATUS=204 run "${F}/08.sites_id_PATCH.sh" example_acct example_site
expect "08 PATCH: a site with no download folder, exit 1, no PATCH" "${RC}:$(calls | grep -c PATCH)" "1:0"
SEQUENCE=$(sequence site_patch_refused "${ONE_SITE}" "${SITE_FULL}")
STATUS=400 run "${F}/08.sites_id_PATCH.sh" example_acct example_site
expect "08 PATCH: a refusal exits 1" "${RC}" "1"
SEQUENCE=
for args in "" "example_acct"; do
    # shellcheck disable=SC2086
    run "${F}/08.sites_id_PATCH.sh" ${args}
    expect "08 PATCH: bad arguments (${args:-none}), exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

SEQUENCE=$(sequence site_test "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body test_ok "${TEST_OK}")
run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: looks the site up, reads it, POSTs testConnection" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/s1id
POST ${S}/operations?operation=testConnection"
expect "09 test: names the site by id, and carries no login" "$(payload 1 | jq -c .)" \
  '{"id":"s1id","name":"example_site","host":"partner.example.com","port":"8022","protocol":"ssh","account":"example_acct"}'
has "09 test: prints the connection" "  connection:      success"
has "09 test: prints the authentication" "  authentication:  success"
SEQUENCE=$(sequence site_test_pw "${ONE_SITE}" "${SITE_FULL}")
SITE_PASSWORD='p@ss "w0rd"' run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: SITE_PASSWORD is sent as the password to try, intact" \
  "$(payload 1 | jq -c '[.password, .usePassword]')" '["p@ss \"w0rd\"","true"]'
SEQUENCE=$(sequence site_test_badpw "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body test_badpw "${TEST_BAD_PW}")
run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: a 200 whose login failed is exit 1" "${RC}" "1"
has "09 test: and says why" "  error:           Password authentication failed."
SEQUENCE=$(sequence site_test_refused "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body test_refused "${TEST_REFUSED}")
run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: a connection that failed is exit 1" "${RC}" "1"
has "09 test: and says why" "  error:           Connection refused"
SEQUENCE=$(sequence site_test_404 "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body test_404 '{"message":"Error validating request","validationErrors":["Site with id s1id not found or not accessible."]}')
STATUS=404 run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: a refusal exits 1 and prints the answer" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'not found or not accessible')" "1:1"
SEQUENCE=
GET_BODY=$(body site_none "${NO_SITE}")
run "${F}/09.sites_operations_POST_test.sh" example_acct example_site
expect "09 test: no such site, exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
GET_BODY=
POST_BODY=

POST_BODY=$(body test_new_ok "${TEST_OK}")
SITE_PASSWORD='p@ss "w0rd"' run "${F}/10.sites_operations_POST_test_new.sh"
expect "10 test new: one call, POST testConnection" "${RC}:$(calls)" "0:POST ${S}/operations?operation=testConnection"
expect "10 test new: john on this server's SSH port by default, the login in username" "$(payload 1 | jq -c .)" \
  '{"name":"example_untested","account":"john","protocol":"ssh","host":"st.example.com","port":"8022","username":"john","password":"p@ss \"w0rd\"","usePassword":"true"}'
has "10 test new: says what it tests" "Testing ssh://st.example.com:8022 as john..."
has "10 test new: prints the connection" "  connection:      success"
SITE_PASSWORD=x run "${F}/10.sites_operations_POST_test_new.sh" example_acct ftp ftp.example.com 21 example_partner
expect "10 test new: the arguments are used" "$(payload 1 | jq -c '[.account, .protocol, .host, .port, .username, .isSecure]')" \
  '["example_acct","ftp","ftp.example.com","21","example_partner",null]'
SITE_PASSWORD=x run "${F}/10.sites_operations_POST_test_new.sh" example_acct http ftp.example.com 443 example_partner true
expect "10 test new: SECURE true sets isSecure" "$(payload 1 | jq -c '.isSecure')" '"true"'
POST_BODY=$(body test_new_bad "${TEST_BAD_PW}")
SITE_PASSWORD=x run "${F}/10.sites_operations_POST_test_new.sh"
expect "10 test new: a login that failed is exit 1" "${RC}" "1"
POST_BODY=$(body test_new_400 '{"message":"Error validating request","validationErrors":["Cannot perform a test operation for a non saved site. Account null does not exist."]}')
SITE_PASSWORD=x STATUS=400 run "${F}/10.sites_operations_POST_test_new.sh"
expect "10 test new: a refusal exits 1 and prints the answer" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'Account null does not exist')" "1:1"
POST_BODY=
run "${F}/10.sites_operations_POST_test_new.sh"
expect "10 test new: no SITE_PASSWORD, exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
for args in "john smb" "john ssh h abc" "john ssh h 22 u maybe"; do
    # shellcheck disable=SC2086
    SITE_PASSWORD=x run "${F}/10.sites_operations_POST_test_new.sh" ${args}
    expect "10 test new: bad arguments (${args}), exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

LISTING='{"connectionStatus":"success","remoteFolder":"/in","errorDetails":"","resultSet":{"returnCount":2,"totalCount":2},"result":[{"fileName":"a.txt","fileSize":"12.00 bytes","filePermissions":"-rw-r-----","lastModifiedTime":"Thu Oct 08 06:41:18 EEST 2026"},{"fileName":"sub","fileSize":"0.00 bytes","filePermissions":"drwxr-x---","lastModifiedTime":"Thu Oct 08 06:41:19 EEST 2026"}]}'
SEQUENCE=$(sequence site_list "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body list_ok "${LISTING}")
run "${F}/11.sites_operations_POST_list.sh" example_acct example_site
expect "11 list: looks the site up, reads it, POSTs listRemoteFolder, always saying which folder, the limit and the folders" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/s1id
POST ${S}/operations?operation=listRemoteFolder&folderToList=downloadFolder&limit=20&includesFolderNamesInResult=true"
expect "11 list: names the site by id, and carries no login" "$(payload 1 | jq -c .)" \
  '{"id":"s1id","name":"example_site","host":"partner.example.com","port":"8022","protocol":"ssh","account":"example_acct"}'
has "11 list: the folder listed" "  folder:      /in"
has "11 list: the count" "  entries:     2 of 2"
has "11 list: a file, with size, permissions and time" "    a.txt  12.00 bytes  -rw-r-----  Thu Oct 08 06:41:18 EEST 2026"
SEQUENCE=$(sequence site_list_up "${ONE_SITE}" "${SITE_FULL}")
run "${F}/11.sites_operations_POST_list.sh" example_acct example_site uploadFolder -1 false
expect "11 list: the folder, the limit and the folders can be given" "$(calls | tail -1)" \
  "POST ${S}/operations?operation=listRemoteFolder&folderToList=uploadFolder&limit=-1&includesFolderNamesInResult=false"
SEQUENCE=$(sequence site_list_missing "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body list_missing '{"connectionStatus":"success","remoteFolder":"/nodir","errorDetails":"No such file: Specified file path is invalid.","resultSet":{"returnCount":0,"totalCount":0},"result":[]}')
run "${F}/11.sites_operations_POST_list.sh" example_acct example_site
expect "11 list: a folder that does not exist (200 with errorDetails) is exit 1" "${RC}" "1"
has "11 list: and says why" "  error:       No such file: Specified file path is invalid."
SEQUENCE=$(sequence site_list_bad "${ONE_SITE}" "${SITE_FULL}")
POST_BODY=$(body list_bad '{"message":"Error validating request","validationErrors":["Remote folder value cannot be empty for a non saved site."]}')
STATUS=400 run "${F}/11.sites_operations_POST_list.sh" example_acct example_site
expect "11 list: a refusal exits 1 and prints the answer" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'cannot be empty')" "1:1"
SEQUENCE=
POST_BODY=
GET_BODY=$(body site_none "${NO_SITE}")
run "${F}/11.sites_operations_POST_list.sh" example_acct example_site
expect "11 list: no such site, exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
GET_BODY=
for args in "john x sideFolder" "john x downloadFolder abc" "john x downloadFolder 5 maybe"; do
    # shellcheck disable=SC2086
    run "${F}/11.sites_operations_POST_list.sh" ${args}
    expect "11 list: bad arguments (${args}), exit 2, nothing sent" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

echo
echo "=== 33.StatisticsSummary ==="
F=33.StatisticsSummary
U="${BASE}/statisticsSummary"
REPORT='{"envId":"Test_ID","schemaId":"https://platform.example.com/schemas/report.json","timestamp":"2026-10-08T08:00:00.000+03:00","granularity":86400000,"report":{"2026-10-08T00:00:00.000+03:00":{"product":"SecureTransport","usage":{"ST.ActiveUsers":0,"ST.TransfersOut":4,"ST.TransfersIn":46,"ST.Transfers":47,"ST.Volume":0},"meta":{}},"2026-10-07T00:00:00.000+03:00":{"product":"SecureTransport","usage":{"ST.ActiveUsers":2,"ST.TransfersOut":6,"ST.TransfersIn":98,"ST.Transfers":98,"ST.Volume":1024},"meta":{}}},"meta":{"companyName":"Example, Inc.","productName":"SecureTransport","productVersion":"5.5-20260101","reportTimeframe":{"startDate":"2026-10-07T00:00:00.000+03:00","endDate":"2026-10-09T00:00:00.000+03:00"},"reportSummary":{"ST.ActiveUsers":2,"ST.TransfersOut":10,"ST.TransfersIn":144,"ST.Transfers":145,"ST.Volume":1024}}}'
GET_BODY=$(body stats_report "${REPORT}")
run "${F}/01.statisticsSummary_generateReport_GET.sh"
expect "01 report: one GET, both dates today, no flags sent" "${RC}:$(calls)" "0:GET ${U}/generateReport?startDate=$(date +%d/%m/%Y)&endDate=$(date +%d/%m/%Y)"
has "01 report: the product and the day length" "Statistics summary of SecureTransport 5.5-20260101, environment Test_ID, one entry per 24 hours"
has "01 report: the period and the number of days" "Period: 2026-10-07T00:00:00.000+03:00 to 2026-10-09T00:00:00.000+03:00 (2 days)"
has "01 report: a day, in date order, from the key" "  2026-10-07  in 98  out 6  transfers 98  users 2  volume 1024"
expect "01 report: the days come in date order, though the server's map has them the other way" "$(printf '%s\n' "${OUT}" | grep -o '^  2026-10-0[78]' | tr '\n' ' ')" "  2026-10-07   2026-10-08 "
has "01 report: the totals" "Total: in 144  out 10  transfers 145  users 2  volume 1024"
run "${F}/01.statisticsSummary_generateReport_GET.sh" 07/10/2026 08/10/2026 true true
expect "01 report: both dates and both flags are sent" "$(calls)" "GET ${U}/generateReport?startDate=07/10/2026&endDate=08/10/2026&includeActiveUsersCount=true&includeIncomingFileVolume=true"
run "${F}/01.statisticsSummary_generateReport_GET.sh" 1/10/2026
expect "01 report: one date is both the start and the end, a short day and month are fine" "$(calls)" "GET ${U}/generateReport?startDate=1/10/2026&endDate=1/10/2026"
run "${F}/01.statisticsSummary_generateReport_GET.sh" 07/10/2026 08/10/2026 false true
expect "01 report: a false flag is not sent" "$(calls)" "GET ${U}/generateReport?startDate=07/10/2026&endDate=08/10/2026&includeIncomingFileVolume=true"
GET_BODY=$(body stats_report_sparse '{"envId":"x","granularity":86400000,"report":{"2026-10-07T00:00:00.000+03:00":{"usage":{}}},"meta":{"reportSummary":{}}}')
run "${F}/01.statisticsSummary_generateReport_GET.sh" 07/10/2026
has "01 report: a day or a total with missing counters reads as 0" "  2026-10-07  in 0  out 0  transfers 0  users 0  volume 0"
GET_BODY=
for args in "2026-10-01" "01-10-2026" "01/10/2026 x" "07/10/2026 08/10/2026 yes" "07/10/2026 08/10/2026 true maybe" "07/10/2026 08/10/2026 true true more" "07/10/2026 08/10/2026 TRUE"; do
    # shellcheck disable=SC2086
    run "${F}/01.statisticsSummary_generateReport_GET.sh" ${args}
    expect "01 report: bad arguments (${args}) exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
GET_BODY=$(body stats_report_400 '{"message":"Error validating request","validationErrors":["Incorrect date frame. '"'"'startDate'"'"' must be before '"'"'endDate'"'"'."]}')
STATUS=400 run "${F}/01.statisticsSummary_generateReport_GET.sh" 08/10/2026 05/10/2026
expect "01 report: a refusal exits 1" "${RC}" "1"
has "01 report: prints the code" "HTTP 400"
has "01 report: and the server's reason" "Incorrect date frame."
GET_BODY=
STATUS=

USERS='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"name":"example_a","lastAccessTime":"October 8, 2026, 8:43 AM","lastAdhocAccessTime":""},{"name":"example_b","lastAccessTime":"October 2, 2026, 7:02 PM","lastAdhocAccessTime":"October 3, 2026, 9:00 AM"}]}'
GET_BODY=$(body stats_users "${USERS}")
run "${F}/02.statisticsSummary_activeUsers_GET.sh"
expect "02 users: one page asked for, 100 at offset 0, no filter" "${RC}:$(calls)" "0:GET ${U}/activeUsers?limit=100&offset=0"
has "02 users: the count" "Users who have logged in: 2"
has "02 users: a user with no ad hoc access shows -" "  example_a  October 8, 2026, 8:43 AM  -"
has "02 users: and one with it shows the time" "  example_b  October 2, 2026, 7:02 PM  October 3, 2026, 9:00 AM"
expect "02 users: a short page ends it, one call" "$(calls | wc -l | tr -d ' ')" "1"
run "${F}/02.statisticsSummary_activeUsers_GET.sh" example_a 2026-10-08 2026-10-09
expect "02 users: the name, from and to are sent as lastAccessTime.from and .to" "$(calls)" "GET ${U}/activeUsers?name=example_a&lastAccessTime.from=2026-10-08&lastAccessTime.to=2026-10-09&limit=100&offset=0"
run "${F}/02.statisticsSummary_activeUsers_GET.sh" "" 2026-10-08
expect "02 users: an empty name is left out, from is sent" "$(calls)" "GET ${U}/activeUsers?lastAccessTime.from=2026-10-08&limit=100&offset=0"
FULL=$(jq -cn '{resultSet:{returnCount:100,totalCount:102},result:[range(100) | {name:"example_\(.)",lastAccessTime:"October 8, 2026, 8:43 AM",lastAdhocAccessTime:""}]}')
REST=$(jq -cn '{resultSet:{returnCount:2,totalCount:102},result:[range(2) | {name:"example_last_\(.)",lastAccessTime:"October 8, 2026, 8:43 AM",lastAdhocAccessTime:""}]}')
GET_BODY=
SEQUENCE=$(sequence stats_users_pages "${FULL}" "${REST}")
run "${F}/02.statisticsSummary_activeUsers_GET.sh"
expect "02 users: a full page is followed by the next one, at offset 100, and a short one ends it" "${RC}:$(calls)" "0:GET ${U}/activeUsers?limit=100&offset=0
GET ${U}/activeUsers?limit=100&offset=100"
expect "02 users: every user of both pages is printed, the count once" "$(printf '%s\n' "${OUT}" | grep -c '^  example_')" "102"
expect "02 users: the header is printed once" "$(printf '%s\n' "${OUT}" | grep -c 'Users who have logged in: 102')" "1"
SEQUENCE=
GET_BODY=$(body stats_users_none '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')
run "${F}/02.statisticsSummary_activeUsers_GET.sh" nobody
expect "02 users: nobody found is exit 0" "${RC}" "0"
has "02 users: says 0" "Users who have logged in: 0"
run "${F}/02.statisticsSummary_activeUsers_GET.sh" a b c d
expect "02 users: four arguments exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=$(body stats_users_400 '{"message":"Error validating request","validationErrors":["Invalid date format. Format must be *EEE, dd MMM yyyy HH:mm:ss Z*, *yyyy-MM-dd* or a timestamp."]}')
STATUS=400 run "${F}/02.statisticsSummary_activeUsers_GET.sh" "" x
expect "02 users: a refusal exits 1 after one call" "${RC}:$(calls | wc -l | tr -d ' ')" "1:1"
has "02 users: with the server's reason" "Invalid date format."
GET_BODY=
STATUS=

POST_BODY=$(body stats_test_ok '{"message":"Connection successful."}')
STATUS=200 run "${F}/03.statisticsSummary_operations_POST_testConnection.sh"
expect "03 test: POST operation=testConnection" "${RC}:$(calls)" "0:POST ${U}/operations?operation=testConnection"
expect "03 test: with no argument and no secret the body is the type alone" "$(payload 1 | jq -c .)" '{"type":"testConnection"}'
has "03 test: says it is using the saved settings" "with the saved settings"
has "03 test: prints the code" "HTTP 200"
has "03 test: and the server's message" "Connection successful."
AMPLIFY_CLIENT_SECRET='example secret "x"' run "${F}/03.statisticsSummary_operations_POST_testConnection.sh" example_client example_zone example_env
expect "03 test: the client id, the secret from the environment, the zone and the environment go in the body" "$(payload 1 | jq -c .)" \
  '{"type":"testConnection","clientId":"example_client","clientSecret":"example secret \"x\"","networkZone":"example_zone","envId":"example_env"}'
has "03 test: says which client" "as client example_client"
expect "03 test: the secret is in the body only, never in the URL" "$(calls | grep -c 'example secret')" "0"
STATUS=202 run "${F}/03.statisticsSummary_operations_POST_testConnection.sh"
expect "03 test: 202 is a success too" "${RC}" "0"
POST_BODY=$(body stats_test_platform '{"error":"invalid_client","error_description":"Invalid client or Invalid client credentials","code":401}')
STATUS=401 run "${F}/03.statisticsSummary_operations_POST_testConnection.sh"
expect "03 test: the platform's refusal exits 1" "${RC}" "1"
has "03 test: shows the code" "HTTP 401"
has "03 test: and that it is the platform that answered, with its reason" "The platform answered: invalid_client: Invalid client or Invalid client credentials"
POST_BODY=$(body stats_test_406 '{"message":"Error validating request","validationErrors":["Test connection to the Amplify Platform failed. Please check the options."]}')
STATUS=406 run "${F}/03.statisticsSummary_operations_POST_testConnection.sh"
expect "03 test: the server's own failure (406) exits 1" "${RC}" "1"
has "03 test: with its reason" "Test connection to the Amplify Platform failed."
POST_BODY=$(body stats_test_apikey '{"code":401,"description":"Invalid access token"}')
STATUS=401 run "${F}/03.statisticsSummary_operations_POST_testConnection.sh"
has "03 test: a token the platform does not accept" "Invalid access token"
run "${F}/03.statisticsSummary_operations_POST_testConnection.sh" a b c d
expect "03 test: four arguments exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
POST_BODY=
STATUS=

echo "=== 07.Subscriptions (05 to 13: the subscriptions operations not called before) ==="
F=07.Subscriptions
S="${BASE}/subscriptions"
LOOK="${S}?account=example_acct&application=example_app&fields=id,application,folder"
ONE_SUB='{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"id":"u1id","application":"example_app","folder":"/example_folder"}]}'
# the list of the account answers every folder of the application: only the exact folder counts
MORE_SUB='{"resultSet":{"returnCount":3,"totalCount":3},"result":[{"id":"u2id","application":"example_app","folder":"/example_folder2"},{"id":"u1id","application":"example_app","folder":"/example_folder"},{"id":"u3id","application":"example_app","folder":"/Example_folder"}]}'
TWO_SAME_SUB='{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"id":"u1id","application":"example_app","folder":"/example_folder"},{"id":"u4id","application":"example_app","folder":"/example_folder"}]}'
NO_SUB='{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}'
SUB_FULL='{"type":"AdvancedRouting","id":"u1id","folder":"/example_folder","account":"example_acct","application":"example_app","maxParallelSitPulls":null,"fileRetentionPeriod":null,"flowAttributes":{"userVars.example_kept":"k"},"schedules":[],"transferConfigurations":[{"id":"t1id","site":"example_site","tag":"PARTNER-IN","outbound":false,"dataTransformations":[],"transferProfile":null,"metadata":{"links":{"site":"https://st.example.com:8444/api/v2.0/sites/s1id"}}}],"metadata":{"links":{"account":"https://st.example.com:8444/api/v2.0/accounts/example_acct"}},"subscriptionEncryptMode":"DEFAULT","createFilesList":{"createFilesListEnabled":null,"createFilesListFilename":null}}'
SUB_BASIC='{"type":"Basic","id":"u1id","folder":"/example_folder","account":"example_acct","application":"example_app","maxParallelSitPulls":6,"fileRetentionPeriod":30,"flowAttributes":{},"schedules":[],"transferConfigurations":[],"metadata":{"links":{}}}'
SUB_BARE='{"type":"AdvancedRouting","id":"u1id","folder":"/example_folder","account":"example_acct","application":"example_app","flowAttributes":{},"schedules":[],"transferConfigurations":[],"metadata":{"links":{}}}'
ARGS="example_acct example_app /example_folder"

GET_BODY=$(body sub_one "${ONE_SUB}")
run "${F}/05.subscriptions_id_HEAD.sh" ${ARGS}
expect "05 HEAD: looks the id up by account, application and folder, then HEADs the id" "${RC}:$(calls)" "0:GET ${LOOK}
HEAD ${S}/u1id"
has "05 HEAD: says the subscription exists, with its id" "The subscription of example_acct on example_app, folder /example_folder, exists, id u1id."
run "${F}/05.subscriptions_id_HEAD.sh"
expect "05 HEAD: the subscription of john on /inbox by default" "$(calls | head -1)" "GET ${S}?account=john&application=AdvancedRoutingApplication&fields=id,application,folder"
STATUS=404 run "${F}/05.subscriptions_id_HEAD.sh" ${ARGS}
expect "05 HEAD: 404 is 'does not exist', exit 1" "${RC}" "1"
GET_BODY=$(body sub_more "${MORE_SUB}")
run "${F}/05.subscriptions_id_HEAD.sh" ${ARGS}
expect "05 HEAD: other folders and another case are not counted, the exact folder is used" "${RC}:$(calls | tail -1)" "0:HEAD ${S}/u1id"
run "${F}/05.subscriptions_id_HEAD.sh" example_acct example_app "/example_*"
expect "05 HEAD: a wildcard is not a folder: none found, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
GET_BODY=$(body sub_same "${TWO_SAME_SUB}")
run "${F}/05.subscriptions_id_HEAD.sh" ${ARGS}
expect "05 HEAD: two matches, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
has "05 HEAD: says how many it found" "Found 2 subscriptions of the account example_acct"
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/05.subscriptions_id_HEAD.sh" ${ARGS}
expect "05 HEAD: no such subscription, exit 1, no HEAD" "${RC}:$(calls | grep -c HEAD)" "1:0"
has "05 HEAD: says none was found" "Found 0 subscriptions"
GET_BODY=

SEQUENCE=$(sequence sub_get "${ONE_SUB}" "${SUB_FULL}" "${SUB_FULL}")
run "${F}/06.subscriptions_id_GET.sh" ${ARGS}
expect "06 GET: looks the id up, reads the subscription, then reads only some fields" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/u1id
GET ${S}/u1id?fields=id,folder,fileRetentionPeriod"
has "06 GET: the type" "  type:              AdvancedRouting"
has "06 GET: the retention is - when not set" "  retention (days):  -"
has "06 GET: the pull site" "  pull sites:        example_site"
has "06 GET: the number of flow attributes" "  flow attributes:   1"
SEQUENCE=$(sequence sub_get_basic "${ONE_SUB}" "${SUB_BASIC}")
run "${F}/06.subscriptions_id_GET.sh" ${ARGS}
has "06 GET: the retention when set" "  retention (days):  30"
has "06 GET: the parallel pulls when set" "  parallel pulls:    6"
has "06 GET: no pull site is -" "  pull sites:        -"
SEQUENCE=$(sequence sub_get_unknown "${ONE_SUB}" '{"message":"Error validating request","validationErrors":["Subscription with id u1id not found or not accessible."]}')
run "${F}/06.subscriptions_id_GET.sh" ${ARGS}
expect "06 GET: an answer with no id, exit 1" "${RC}" "1"
SEQUENCE=

SEQUENCE=$(sequence sub_put "${ONE_SUB}" "${SUB_FULL}")
STATUS=204 run "${F}/07.subscriptions_id_PUT.sh" ${ARGS} 9
expect "07 PUT: looks the id up, reads the subscription, PUTs it" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/u1id
PUT ${S}/u1id"
expect "07 PUT: sends the whole subscription back, pull site and its id kept, only the limit changed, the top level metadata dropped" \
  "$(payload 1 | jq -c .)" \
  '{"type":"AdvancedRouting","id":"u1id","folder":"/example_folder","account":"example_acct","application":"example_app","maxParallelSitPulls":9,"fileRetentionPeriod":null,"flowAttributes":{"userVars.example_kept":"k"},"schedules":[],"transferConfigurations":[{"id":"t1id","site":"example_site","tag":"PARTNER-IN","outbound":false,"dataTransformations":[],"transferProfile":null,"metadata":{"links":{"site":"https://st.example.com:8444/api/v2.0/sites/s1id"}}}],"subscriptionEncryptMode":"DEFAULT","createFilesList":{"createFilesListEnabled":null,"createFilesListFilename":null}}'
has "07 PUT: prints the value before" "maxParallelSitPulls of the subscription is now (not set)."
has "07 PUT: prints the code" "HTTP 204"
SEQUENCE=$(sequence sub_put_basic "${ONE_SUB}" "${SUB_BASIC}")
STATUS=204 run "${F}/07.subscriptions_id_PUT.sh" ${ARGS}
has "07 PUT: prints the value before when set" "maxParallelSitPulls of the subscription is now 6."
expect "07 PUT: 2 by default, a number" "$(payload 1 | jq -c .maxParallelSitPulls)" "2"
SEQUENCE=$(sequence sub_put_zero "${ONE_SUB}" "${SUB_FULL}")
STATUS=204 run "${F}/07.subscriptions_id_PUT.sh" ${ARGS} 0
expect "07 PUT: 0, no limit, is a value (a number, not a string)" "$(payload 1 | jq -c .maxParallelSitPulls)" "0"
SEQUENCE=$(sequence sub_put_refused "${ONE_SUB}" "${SUB_FULL}")
STATUS=400 run "${F}/07.subscriptions_id_PUT.sh" ${ARGS} 3
expect "07 PUT: a refusal exits 1" "${RC}" "1"
SEQUENCE=$(sequence sub_put_unreadable "${ONE_SUB}" '{"message":"Error validating request"}')
STATUS=204 run "${F}/07.subscriptions_id_PUT.sh" ${ARGS} 3
expect "07 PUT: a subscription that cannot be read: exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
SEQUENCE=
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/07.subscriptions_id_PUT.sh" ${ARGS} 3
expect "07 PUT: no such subscription, exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY=
for args in "" "example_acct" "example_acct example_app" "${ARGS} abc" "${ARGS} -1" "${ARGS} 2.5"; do
    run "${F}/07.subscriptions_id_PUT.sh" ${args}
    expect "07 PUT: arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done

SEQUENCE=$(sequence sub_patch "${ONE_SUB}" "${SUB_FULL}")
STATUS=204 run "${F}/08.subscriptions_id_PATCH.sh" ${ARGS}
expect "08 PATCH: looks the id up, reads the subscription, PATCHes it" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/u1id
PATCH ${S}/u1id"
expect "08 PATCH: adds the flow attribute, with the default value" "$(payload 1 | jq -c .)" \
  '[{"op":"add","path":"/flowAttributes/userVars.example_note","value":"example"}]'
has "08 PATCH: the attribute was not set" "The flow attribute userVars.example_note is now (not set)."
has "08 PATCH: prints the code" "HTTP 204"
SEQUENCE=$(sequence sub_patch_value "${ONE_SUB}" "$(printf '%s' "${SUB_FULL}" | jq -c '.flowAttributes["userVars.example_note"] = "before"')")
STATUS=204 run "${F}/08.subscriptions_id_PATCH.sh" ${ARGS} "a value with spaces"
expect "08 PATCH: the value given is sent as a string" "$(payload 1 | jq -c .)" \
  '[{"op":"add","path":"/flowAttributes/userVars.example_note","value":"a value with spaces"}]'
has "08 PATCH: prints the value before" "The flow attribute userVars.example_note is now before."
SEQUENCE=$(sequence sub_patch_refused "${ONE_SUB}" "${SUB_FULL}")
STATUS=400 run "${F}/08.subscriptions_id_PATCH.sh" ${ARGS}
expect "08 PATCH: a refusal exits 1" "${RC}" "1"
SEQUENCE=
for args in "" "example_acct" "example_acct example_app"; do
    run "${F}/08.subscriptions_id_PATCH.sh" ${args}
    expect "08 PATCH: arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
run "${F}/08.subscriptions_id_PATCH.sh" ${ARGS} " "
expect "08 PATCH: a blank value exits 2 and sends nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/08.subscriptions_id_PATCH.sh" ${ARGS}
expect "08 PATCH: no such subscription, exit 1, no PATCH" "${RC}:$(calls | grep -c PATCH)" "1:0"
GET_BODY=

PULL_ANSWER='{"message":"Transfer pull event has been successfully submitted for processing","link":"https://st.example.com:8444/api/v2.0/logs/transfers?operationIndex=abc-123&startTimeAfter=Thu%2C+08+Oct+2026"}'
SEQUENCE=$(sequence sub_pull "${ONE_SUB}" "${SUB_FULL}")
POST_BODY=$(body sub_pull_answer "${PULL_ANSWER}")
STATUS=202 run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS}
expect "09 Pull: looks the id up, reads the subscription, POSTs the operation" "${RC}:$(calls)" "0:GET ${LOOK}
GET ${S}/u1id
POST ${S}/u1id/operations?operation=Pull"
expect "09 Pull: pulls with the PARTNER-IN site of the subscription" "$(payload 1 | jq -c .)" '{"type":"pull","site":"example_site"}'
has "09 Pull: prints the code" "HTTP 202"
has "09 Pull: prints the message" "Transfer pull event has been successfully submitted for processing"
has "09 Pull: prints the operationIndex, to follow it in the transfer log" "operationIndex: abc-123"
SEQUENCE=$(sequence sub_pull_site "${ONE_SUB}" "${SUB_FULL}")
STATUS=202 run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS} other_site
expect "09 Pull: a site given is used" "$(payload 1 | jq -c .)" '{"type":"pull","site":"other_site"}'
SEQUENCE=$(sequence sub_pull_bare "${ONE_SUB}" "${SUB_BARE}")
STATUS=202 run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS}
expect "09 Pull: no pull site and none given: exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
has "09 Pull: says so" "The subscription has no pull site"
SEQUENCE=$(sequence sub_pull_bare_site "${ONE_SUB}" "${SUB_BARE}")
STATUS=202 run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS} other_site
expect "09 Pull: no pull site of its own but one given: it pulls with that" "${RC}:$(payload 1 | jq -c .site)" '0:"other_site"'
SEQUENCE=$(sequence sub_pull_refused "${ONE_SUB}" "${SUB_FULL}")
POST_BODY=$(body sub_pull_406 '{"message":"Error validating request","validationErrors":["Site '"'"'x'"'"' was not found."]}')
STATUS=406 run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS} x
expect "09 Pull: a refusal exits 1" "${RC}" "1"
has "09 Pull: with the code" "HTTP 406"
has "09 Pull: and the server's answer" "was not found."
SEQUENCE=
POST_BODY=
for args in "" "example_acct" "example_acct example_app"; do
    run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${args}
    expect "09 Pull: arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/09.subscriptions_id_operations_POST_pull.sh" ${ARGS}
expect "09 Pull: no such subscription, exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
GET_BODY=

GET_BODY=$(body sub_one "${ONE_SUB}")
POST_BODY=$(body sub_clear_answer '{"message":"Clear pull history for subscription with id u1id was successfully submitted for processing."}')
STATUS=202 run "${F}/10.subscriptions_id_operations_POST_clearPullHistory.sh" ${ARGS}
expect "10 ClearPullHistory: looks the id up, POSTs the operation, no body" "${RC}:$(calls):$(payload 1)" "0:GET ${LOOK}
POST ${S}/u1id/operations?operation=ClearPullHistory:"
has "10 ClearPullHistory: prints the code" "HTTP 202"
has "10 ClearPullHistory: prints the message" "Clear pull history for subscription with id u1id was successfully submitted for processing."
POST_BODY=$(body sub_clear_404 '{"message":"HTTP 404 Not Found"}')
STATUS=404 run "${F}/10.subscriptions_id_operations_POST_clearPullHistory.sh" ${ARGS}
expect "10 ClearPullHistory: a refusal exits 1 and shows the answer" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'HTTP 404 Not Found')" "1:1"
POST_BODY=
for args in "" "example_acct" "example_acct example_app"; do
    run "${F}/10.subscriptions_id_operations_POST_clearPullHistory.sh" ${args}
    expect "10 ClearPullHistory: arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/10.subscriptions_id_operations_POST_clearPullHistory.sh" ${ARGS}
expect "10 ClearPullHistory: no such subscription, exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"

GET_BODY=$(body sub_one "${ONE_SUB}")
STATUS=204 run "${F}/11.subscriptions_id_operations_POST_purge.sh" ${ARGS}
expect "11 Purge: looks the id up, POSTs the operation, no body" "${RC}:$(calls):$(payload 1)" "0:GET ${LOOK}
POST ${S}/u1id/operations?operation=Purge:"
has "11 Purge: prints the code" "HTTP 204"
STATUS=404 run "${F}/11.subscriptions_id_operations_POST_purge.sh" ${ARGS}
expect "11 Purge: a refusal exits 1" "${RC}" "1"
for args in "" "example_acct" "example_acct example_app"; do
    run "${F}/11.subscriptions_id_operations_POST_purge.sh" ${args}
    expect "11 Purge: arguments '${args}' exit 2 and send nothing" "${RC}:$(calls | wc -l | tr -d ' ')" "2:0"
done
GET_BODY=$(body sub_none "${NO_SUB}")
run "${F}/11.subscriptions_id_operations_POST_purge.sh" ${ARGS}
expect "11 Purge: no such subscription, exit 1, no POST" "${RC}:$(calls | grep -c POST)" "1:0"
GET_BODY=

STATUS=201 LOCATION=newid run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 POST types: an application and a subscription for each of four types" "${RC}:$(calls)" "0:POST ${BASE}/applications
POST ${S}
POST ${BASE}/applications
POST ${S}
POST ${BASE}/applications
POST ${S}
POST ${BASE}/applications
POST ${S}"
expect "12 POST types: the Basic application" "$(payload 1 | jq -c .)" '{"type":"Basic","name":"ExampleBasicApplication","notes":"Created by 07.Subscriptions"}'
expect "12 POST types: the Basic subscription, with only the four fields" "$(payload 2 | jq -c .)" \
  '{"type":"Basic","account":"example_acct","application":"ExampleBasicApplication","folder":"/example_Basic"}'
expect "12 POST types: the HumanSystem subscription has a rule" "$(payload 4 | jq -c .)" \
  '{"type":"HumanSystem","account":"example_acct","application":"ExampleHumanSystemApplication","folder":"/example_HumanSystem","rules":[{"enabled":true,"recipientPattern":"*","fileFilterPattern":"*.txt","targetFolder":"/example_targets"}]}'
expect "12 POST types: the MBFT subscription" "$(payload 6 | jq -c .)" \
  '{"type":"MBFT","account":"example_acct","application":"ExampleMBFTApplication","folder":"/example_MBFT"}'
expect "12 POST types: the StandardRouter application and subscription, with the subscriber's ID" "$(payload 7 | jq -c .type):$(payload 8 | jq -c .)" \
  '"StandardRouter":{"type":"StandardRouter","account":"example_acct","application":"ExampleStandardRouterApplication","folder":"/example_StandardRouter","subscriberID":"EXAMPLE_SUBSCRIBER"}'
expect "12 POST types: prints each new id four times" "$(printf '%s\n' "${OUT}" | grep -c 'New subscription ID: newid')" "4"
run "${F}/12.subscriptions_POST_types.sh"
expect "12 POST types: john by default" "$(payload 2 | jq -r .account)" "john"
STATUS=400 run "${F}/12.subscriptions_POST_types.sh" example_acct
expect "12 POST types: a refused subscription exits 1, the other types are still tried" "${RC}:$(calls | grep -c "POST ${S}$")" "1:4"
STATUS=

GET_BODY=$(body sub_types '{"result":[{"id":"b1id","application":"ExampleBasicApplication","folder":"/example_Basic"},{"id":"h1id","application":"ExampleHumanSystemApplication","folder":"/example_HumanSystem"},{"id":"m1id","application":"ExampleMBFTApplication","folder":"/example_MBFT"},{"id":"r1id","application":"ExampleStandardRouterApplication","folder":"/example_StandardRouter"}]}')
STATUS=204 run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 DELETE types: for each type, a lookup, the subscription with purge=true, the application" "${RC}:$(calls)" "0:GET ${S}?account=example_acct&application=ExampleBasicApplication&fields=id,application,folder
DELETE ${S}/b1id?purge=true
DELETE ${BASE}/applications/ExampleBasicApplication
GET ${S}?account=example_acct&application=ExampleHumanSystemApplication&fields=id,application,folder
DELETE ${S}/h1id?purge=true
DELETE ${BASE}/applications/ExampleHumanSystemApplication
GET ${S}?account=example_acct&application=ExampleMBFTApplication&fields=id,application,folder
DELETE ${S}/m1id?purge=true
DELETE ${BASE}/applications/ExampleMBFTApplication
GET ${S}?account=example_acct&application=ExampleStandardRouterApplication&fields=id,application,folder
DELETE ${S}/r1id?purge=true
DELETE ${BASE}/applications/ExampleStandardRouterApplication"
expect "13 DELETE types: prints the code eight times" "$(printf '%s\n' "${OUT}" | grep -c 'HTTP 204')" "8"
run "${F}/13.subscriptions_id_DELETE_types.sh"
expect "13 DELETE types: john by default" "$(calls | head -1)" "GET ${S}?account=john&application=ExampleBasicApplication&fields=id,application,folder"
STATUS=400 run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 DELETE types: a refused delete exits 1" "${RC}" "1"
GET_BODY=$(body sub_none "${NO_SUB}")
STATUS=204 run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 DELETE types: no subscription found: only the applications are deleted, exit 0" "${RC}:$(calls | grep -c '^DELETE .*/applications/'):$(calls | grep -c '^DELETE .*/subscriptions/')" "0:4:0"
has "13 DELETE types: says none was deleted" "none deleted"
GET_BODY=$(body sub_two '{"result":[{"id":"b1id","application":"ExampleBasicApplication","folder":"/example_Basic"},{"id":"b2id","application":"ExampleBasicApplication","folder":"/example_Basic"}]}')
run "${F}/13.subscriptions_id_DELETE_types.sh" example_acct
expect "13 DELETE types: two matches: nothing deleted, exit 1" "${RC}:$(calls | grep -c '^DELETE .*/subscriptions/')" "1:0"
GET_BODY=
STATUS=

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_api: PASS"
else
    echo "test_bash_admin_api: FAIL"
fi
exit "${FAILED}"
