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
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_api: PASS"
else
    echo "test_bash_admin_api: FAIL"
fi
exit "${FAILED}"
