#!/bin/bash
# ==============================================================================
# The older Admin write examples that were brought up to the house rules, run
# against a stub curl: 12.BusinessUnits/01, 13.Configurations/39 to 47,
# 15.Transfers/01, 17.AccessPolicies/02, 18.AccountSetup/02 and 04,
# 20.AdministrativeRoles/02, 06 and 07, and 21.Administrators/02 to 07.
#
# For each: a bare run that sends nothing where an argument is required (exit
# 2), the exact URL and body, the HTTP code it prints, exit 1 when the server
# refuses (4xx or 5xx) with the server's reason, names URL-encoded, and for the
# deletes that what is deleted is read and printed first, that nothing is
# deleted when the read fails, and that the administrator logged in as is never
# deleted. The bat twins cannot run here: they are checked against the bash
# ones for the exit codes and the HTTP print, and for the one typo that broke
# sixteen of them.
#
# The 14.ExpressionLanguage examples are in test_bash_expression_language.sh.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
ADMIN_TREE="${REPO}/Admin/API 2.0/bash"
BAT_TREE="${REPO}/Admin/API 2.0/bat"

WORK="${TESTS_DIR}/output/bash_admin_sweep_b"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/admin"

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

# body NAME JSON: a canned answer, in a file
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
# rules TEXT FILE [TEXT FILE...]: answers by URL, for a script that reads several things
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# run FOLDER/SCRIPT ARGS...: GET_BODY and RULES are what the GETs answer; LOCATION, the id in the Location of a POST;
# ST_GET, ST_POST, ST_PUT, ST_PATCH, ST_DELETE the status of each method (200, 201, 204, 204, 204 when not set);
# ST_POST_SEQ and ST_PUT_SEQ a status for each call in turn; POST_BODY is what a POST answers with, ERR_BODY what a PUT, PATCH or DELETE does
run() {
    local rel="$1"; shift
    mkdir -p "${WORK}/admin/$(dirname "${rel}")"
    cp "${ADMIN_TREE}/${rel}" "${WORK}/admin/${rel}"
    rm -f "${WORK}/counter."*
    OUT=$(cd "${WORK}/admin/$(dirname "${rel}")" && PATH="${WORK}/bin:${PATH}" STUB_COUNTER="${WORK}/counter" STUB_CURL_PRINT_CODE=1 \
          STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_CURL_LOCATION_ID="${LOCATION:-}" STUB_BODY_OTHER="${ERR_BODY:-}" \
          STUB_STATUS_GET="${ST_GET:-200}" STUB_STATUS_POST="${ST_POST:-201}" STUB_STATUS_PUT="${ST_PUT:-204}" \
          STUB_STATUS_PATCH="${ST_PATCH:-204}" STUB_STATUS_DELETE="${ST_DELETE:-204}" \
          STUB_STATUS_POST_SEQ="${ST_POST_SEQ:-}" STUB_STATUS_PUT_SEQ="${ST_PUT_SEQ:-}" \
          bash "./$(basename "${rel}")" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | grep -c .; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
# an answer the way the server refuses
REFUSAL=$(body refusal '{"message":"Error validating request","validationErrors":["Some reason the server gives."],"docLink":"x"}')

echo "=== 12.BusinessUnits/01.businessUnits_POST.sh ==="
F=12.BusinessUnits
S=01.businessUnits_POST.sh
LOCATION=Finance run "${F}/${S}"
expect "01: bare, POSTs Finance with /home/fin and exits 0" "${RC}:$(calls)" "0:POST ${BASE}/businessUnits"
expect "01: the body, built by jq" "$(payload 1 | jq -c .)" '{"name":"Finance","baseFolder":"/home/fin"}'
has "01: prints the HTTP code" "HTTP 201"
has "01: and where the unit is, from Location" "It is at ${BASE}/businessUnits/Finance"
run "${F}/${S}" 'Sales "East"' /home/sales
expect "01: a name with quotes goes through jq, and the folder as given" "$(payload 1 | jq -c '[.name, .baseFolder]')" '["Sales \"East\"","/home/sales"]'
BU_REFUSED=$(body bu_refused '{"message":"Error validating request","validationErrors":["Business unit name already exists. Business unit base folder is already in use or it is not valid. "],"docLink":"x"}')
ST_POST=400 POST_BODY="${BU_REFUSED}" run "${F}/${S}"
expect "01: a 400 (a name that exists) is exit 1" "${RC}" "1"
has "01: prints HTTP 400 and the reason" "HTTP 400"
has "01: and what the server said" "Business unit name already exists."
run "${F}/${S}" "   "
expect "01: a blank name is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run "${F}/${S}" Sales home/sales
expect "01: a base folder that is not absolute is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: and says so" "BASE_FOLDER must be an absolute path"
run "${F}/${S}" Sales /home/sales extra
expect "01: three arguments are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo
echo "=== 13.Configurations/38 to 47 (external stores and S3 storage profiles) ==="
F=13.Configurations
STORE=$(body store '{"name":"example_vault","method":"GET","baseUrl":"https://vault.example.com:8200","uri":"/v1/secret/data","pathPrefix":"$.data.data","cacheTimeout":600,"readTimeout":30,"auth":{"baseUrl":"https://vault.example.com:8200","uri":"/v1/auth/approle/login"}}')
STORE_404=$(body store_404 '{"message":"Error validating request","validationErrors":["Cannot find external store with name '"'"'example_nobody'"'"' or external store configuration is not accessible"]}')

GET_BODY="${STORE}" run "${F}/39.configurations_externalStores_name_GET.sh"
expect "39 GET: example_vault by default" "${RC}:$(calls)" "0:GET ${BASE}/configurations/externalStores/example_vault"
GET_BODY="${STORE}" run "${F}/39.configurations_externalStores_name_GET.sh" "my store"
expect "39 GET: a name with a space is encoded in the path" "$(calls)" "GET ${BASE}/configurations/externalStores/my%20store"
GET_BODY="${STORE}" run "${F}/39.configurations_externalStores_name_GET.sh" "a/b"
expect "39 GET: a name with a slash is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
GET_BODY="${STORE_404}" ST_GET=404 run "${F}/39.configurations_externalStores_name_GET.sh"
expect "39 GET: a store that is not there is exit 1" "${RC}" "1"

GET_BODY="${STORE}" run "${F}/40.configurations_externalStores_name_PUT.sh" 45 "my store"
expect "40 PUT: reads, then PUTs, both by the encoded name" "${RC}:$(calls)" "0:GET ${BASE}/configurations/externalStores/my%20store
PUT ${BASE}/configurations/externalStores/my%20store"
expect "40 PUT: the whole store back with only readTimeout changed" "$(payload 1 | jq -c '[.readTimeout, .cacheTimeout, .name]')" '[45,600,"example_vault"]'
has "40 PUT: says what it was before" "readTimeout of my store is now 30."
GET_BODY="${STORE_404}" ST_GET=404 run "${F}/40.configurations_externalStores_name_PUT.sh" 45
expect "40 PUT: a store that cannot be read is exit 1 and sends no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
has "40 PUT: says the HTTP code" "HTTP 404"
GET_BODY="${STORE}" ST_PUT=400 ERR_BODY="${REFUSAL}" run "${F}/40.configurations_externalStores_name_PUT.sh" 45
expect "40 PUT: prints HTTP 400 and exits 1 when the PUT is refused" "${RC}:$(printf '%s' "${OUT}" | grep -c 'HTTP 400')" "1:1"
run "${F}/40.configurations_externalStores_name_PUT.sh" 0
expect "40 PUT: 0 seconds is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

run "${F}/41.configurations_externalStores_name_PATCH.sh" 120 "my store"
expect "41 PATCH: one PATCH, the encoded name" "${RC}:$(calls)" "0:PATCH ${BASE}/configurations/externalStores/my%20store"
expect "41 PATCH: a JSON Patch built by jq, the number a number" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/cacheTimeout","value":120}]'
ST_PATCH=404 run "${F}/41.configurations_externalStores_name_PATCH.sh" 120
expect "41 PATCH: 404 is exit 1, HTTP printed" "${RC}:$(printf '%s' "${OUT}" | grep -c 'HTTP 404')" "1:1"
run "${F}/41.configurations_externalStores_name_PATCH.sh" abc
expect "41 PATCH: a number that is not one is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run "${F}/41.configurations_externalStores_name_PATCH.sh" 5 "a/b"
expect "41 PATCH: a slash in the name is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

GET_BODY=$(body test_ok '{"connectionStatus":"Success","authenticationStatus":"Success","fetchStatus":"Success","response":{"jsonData":{"k":"v"}}}') \
  ST_POST=200 POST_BODY=$(body test_ok_post '{"connectionStatus":"Success","authenticationStatus":"Success","fetchStatus":"Success","response":{"jsonData":{"k":"v"}}}') \
  run "${F}/42.configurations_externalStores_name_operations_POST_test.sh" example/db "my store"
expect "42 test: POST with the operation in the query, the encoded name" "${RC}:$(calls)" "0:POST ${BASE}/configurations/externalStores/my%20store/operations?operation=test"
expect "42 test: the secret path in the body" "$(payload 1 | jq -c .)" '{"secretPath":"example/db"}'
run "${F}/42.configurations_externalStores_name_operations_POST_test.sh" example/db "a/b"
expect "42 test: a slash in the name is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

ST_POST=200 POST_BODY=$(body cleared '{"message":"Cache was cleared successfully"}') run "${F}/43.configurations_externalStores_name_operations_POST_clearCache.sh" example/db "my store"
expect "43 clearCache: POST with the encoded name" "${RC}:$(calls)" "0:POST ${BASE}/configurations/externalStores/my%20store/operations?operation=clearCache"
ST_POST=404 POST_BODY="${REFUSAL}" run "${F}/43.configurations_externalStores_name_operations_POST_clearCache.sh" example/db
expect "43 clearCache: a refusal is exit 1, with the reason the server gives and not only its generic message" "${RC}:$(printf '%s' "${OUT}" | grep -c 'Some reason the server gives.')" "1:1"

echo "  -- 44 DELETE"
S=44.configurations_externalStores_name_DELETE.sh
GET_BODY="${STORE}" run "${F}/${S}"
expect "44: reads the store, then deletes it" "${RC}:$(calls)" "0:GET ${BASE}/configurations/externalStores/example_vault
DELETE ${BASE}/configurations/externalStores/example_vault"
has "44: says what it deletes, before it does" "Deleting the external store example_vault (https://vault.example.com:8200/v1/secret/data, cached 600s)..."
has "44: prints the HTTP code" "HTTP 204"
GET_BODY="${STORE}" run "${F}/${S}" "my store"
expect "44: the name is encoded in both calls" "$(calls)" "GET ${BASE}/configurations/externalStores/my%20store
DELETE ${BASE}/configurations/externalStores/my%20store"
GET_BODY="${STORE}" ST_DELETE=400 ERR_BODY="${REFUSAL}" run "${F}/${S}"
expect "44: a delete the server refuses is exit 1" "${RC}" "1"
has "44: with HTTP 400" "HTTP 400"
GET_BODY="${STORE_404}" ST_GET=404 run "${F}/${S}" example_nobody
expect "44: a store that cannot be read is exit 1 and nothing is deleted" "${RC}:$(calls | grep -c DELETE)" "1:0"
has "44: says nothing was deleted" "nothing was deleted"
GET_BODY="${STORE}" run "${F}/${S}" "a/b"
expect "44: a slash in the name is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "  -- 45 register, 46 test, 47 unregister"
REG=$(body registry '{"name":"StorageProfiles.S3.Registry","values":["other","zeta"]}')
GET_BODY="${REG}" run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket us-east-1 http://s3.example.com:9000
expect "45: reads the registry, puts the list back with the profile, then its settings" "${RC}:$(calls)" "0:GET ${BASE}/configurations/options/StorageProfiles.S3.Registry
PUT ${BASE}/configurations/options
PUT ${BASE}/configurations/options"
expect "45: the registry body is built by jq: the others, and the profile, sorted" "$(payload 1 | jq -c .)" '[{"name":"StorageProfiles.S3.Registry","values":["example_s3","other","zeta"]}]'
expect "45: the settings: bucket, region, endpoint" "$(payload 2 | jq -c '[.[] | select(.name | test("Bucket|Region|CustomEndpointUrl")) | .values[0]]')" '["example-bucket","us-east-1","http://s3.example.com:9000"]'
GET_BODY="${REG}" S3_ACCESS_KEY=AKEXAMPLE S3_SECRET_KEY='s3 "secret"' run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket
expect "45: the keys come from the environment, into the body, whatever they hold" "$(payload 2 | jq -c '[.[] | select(.name | test("AccessKey|SecretKey")) | .values[0]]')" '["AKEXAMPLE","s3 \"secret\""]'
hasnt "45: a secret is never printed" "AKEXAMPLE"
GET_BODY="${STORE_404}" ST_GET=500 run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket
expect "45: a registry that cannot be read is exit 1 and nothing is put" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY="${REG}" ST_PUT_SEQ="204 400" ERR_BODY="${REFUSAL}" run "${F}/45.configurations_storageProfiles_options_PUT_register.sh" example-bucket
expect "45: settings refused after the registration is exit 1" "${RC}" "1"
has "45: and says the name is in the registry all the same, and how to remove it" "47.configurations_storageProfiles_options_PUT_unregister.sh removes it"
run "${F}/45.configurations_storageProfiles_options_PUT_register.sh"
expect "45: no bucket is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

ST_POST=204 run "${F}/46.configurations_storageProfiles_name_operations_POST_test.sh" "my profile"
expect "46: POST with the encoded profile name" "${RC}:$(calls)" "0:POST ${BASE}/configurations/storageProfiles/my%20profile/operations?operation=test"
ST_POST=404 POST_BODY="${STORE_404}" run "${F}/46.configurations_storageProfiles_name_operations_POST_test.sh" no_such
expect "46: 404 is exit 1" "${RC}" "1"
run "${F}/46.configurations_storageProfiles_name_operations_POST_test.sh" "a/b"
expect "46: a slash in the name is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

REG_ONE=$(body registry_one '{"name":"StorageProfiles.S3.Registry","values":["other","example_s3"]}')
GET_BODY="${REG_ONE}" run "${F}/47.configurations_storageProfiles_options_PUT_unregister.sh"
expect "47: reads the registry, puts it back without the profile" "${RC}:$(calls)" "0:GET ${BASE}/configurations/options/StorageProfiles.S3.Registry
PUT ${BASE}/configurations/options"
expect "47: the body, by jq" "$(payload 1 | jq -c .)" '[{"name":"StorageProfiles.S3.Registry","values":["other"]}]'
GET_BODY=$(body registry_only '{"name":"StorageProfiles.S3.Registry","values":["example_s3"]}') run "${F}/47.configurations_storageProfiles_options_PUT_unregister.sh"
expect "47: an emptied registry is [\"\"], never []" "$(payload 1 | jq -c '.[0].values')" '[""]'
GET_BODY="${STORE_404}" ST_GET=500 run "${F}/47.configurations_storageProfiles_options_PUT_unregister.sh"
expect "47: a registry that cannot be read is exit 1 and nothing is put (an empty list would drop every profile)" "${RC}:$(calls | grep -c PUT)" "1:0"

echo
echo "=== 15.Transfers/01.transfers_operations_POST_pull.sh ==="
F=15.Transfers
S=01.transfers_operations_POST_pull.sh
POST_BODY=$(body pull_ok '{"message":"Pull accepted","link":"x"}') ST_POST=202 run "${F}/${S}"
expect "01: bare, POSTs the pull and exits 0 on 202" "${RC}:$(calls)" "0:POST ${BASE}/transfers/operations?operation=pull"
expect "01: john, SSH_PULL, /inbox, not waiting" "$(payload 1 | jq -c .)" '{"accountName":"john","site":"SSH_PULL","destinationDirectory":"/inbox","awaitResult":false}'
has "01: prints the HTTP code on its own line" "HTTP 202"
has "01: and the answer" "Pull accepted"
ST_POST=202 run "${F}/${S}" jane "my site" /in/x
expect "01: account, site and folder as given, by jq" "$(payload 1 | jq -c '[.accountName, .site, .destinationDirectory]')" '["jane","my site","/in/x"]'
POST_BODY=$(body pull_404 '{"message":"Error validating request","validationErrors":["Cannot find account with name example_nobody or it is not accessible"]}') ST_POST=404 run "${F}/${S}" example_nobody
expect "01: 404 is exit 1, the reason printed" "${RC}:$(printf '%s' "${OUT}" | grep -c 'Cannot find account')" "1:1"
has "01: with the HTTP code" "HTTP 404"
ST_POST=200 run "${F}/${S}"
expect "01: 200 is not the 202 of an accepted pull: exit 1" "${RC}" "1"
run "${F}/${S}" "  "
expect "01: a blank account is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run "${F}/${S}" a b /c d
expect "01: four arguments are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo
echo "=== 17.AccessPolicies/02.accessPolicies_POST.sh ==="
F=17.AccessPolicies
S=02.accessPolicies_POST.sh
LOCATION=4 run "${F}/${S}"
expect "02: POST /accessPolicies, exit 0 on 201" "${RC}:$(calls)" "0:POST ${BASE}/accessPolicies"
expect "02: the body, built by jq" "$(payload 1 | jq -c .)" '{"connectionType":"host","database":"example_db","user":"example_user","address":"samehost","authMethod":"reject"}'
has "02: the code is read with -w, and printed" "HTTP 201"
has "02: and the new rule's id from Location" "The new rule is number 4."
POST_BODY=$(body ap_400 '{"message":"Error validating request","validationErrors":["Valid auth method values are: reject, trust, scram-sha-256, md5, password."]}') ST_POST=400 run "${F}/${S}"
expect "02: a 400 is exit 1" "${RC}" "1"
has "02: with the reasons" "Valid auth method values are"
expect "02: the script does not read the status with grep and awk any more" "$(grep -c 'awk' "${ADMIN_TREE}/${F}/${S}")" "0"

echo
echo "=== 18.AccountSetup/02 and 04 ==="
F=18.AccountSetup
GET_BODY=$(body setup '{"accountSetup":{"account":{"name":"example_setup","type":"user","homeFolder":"/home/example_setup"},"certificates":{"login":[],"partner":[],"private":[]},"sites":[],"transferProfiles":[],"routes":[],"subscriptions":[]}}') \
  run "${F}/02.accountSetup_name_GET.sh" "my account"
expect "02 GET: the account name is encoded in the path" "${RC}:$(calls)" "0:GET ${BASE}/accountSetup/my%20account"
ACC=$(body acc '{"type":"user","homeFolder":"/home/example_setup","uid":"41733"}')
GET_BODY="${ACC}" run "${F}/04.accounts_name_DELETE.sh"
expect "04 DELETE: bare, reads example_setup, then deletes it" "${RC}:$(calls)" "0:GET ${BASE}/accounts/example_setup?fields=type,homeFolder,uid
DELETE ${BASE}/accounts/example_setup"
has "04 DELETE: says what it deletes" "Deleting the account example_setup (type user, home folder /home/example_setup, uid 41733)"
has "04 DELETE: prints the HTTP code" "HTTP 204"
GET_BODY="${ACC}" run "${F}/04.accounts_name_DELETE.sh" "my account"
expect "04 DELETE: any account can be named, encoded" "$(calls | tail -1)" "DELETE ${BASE}/accounts/my%20account"
GET_BODY="${STORE_404}" ST_GET=404 run "${F}/04.accounts_name_DELETE.sh"
expect "04 DELETE: an account that is not there is not an error, and nothing is deleted" "${RC}:$(calls | grep -c DELETE)" "0:0"
has "04 DELETE: says so" "does not exist"
GET_BODY="${STORE_404}" ST_GET=500 run "${F}/04.accounts_name_DELETE.sh"
expect "04 DELETE: a read that fails is exit 1 and nothing is deleted" "${RC}:$(calls | grep -c DELETE)" "1:0"
GET_BODY="${ACC}" ST_DELETE=400 ERR_BODY="${REFUSAL}" run "${F}/04.accounts_name_DELETE.sh"
expect "04 DELETE: a refused delete is exit 1, HTTP 400 printed" "${RC}:$(printf '%s' "${OUT}" | grep -c 'HTTP 400')" "1:1"
run "${F}/04.accounts_name_DELETE.sh" a b
expect "04 DELETE: two arguments are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo
echo "=== 20.AdministrativeRoles/02, 06 and 07 ==="
F=20.AdministrativeRoles
LOCATION=example_role run "${F}/02.administrativeRoles_POST.sh"
expect "02 POST: bare, one POST, exit 0" "${RC}:$(calls)" "0:POST ${BASE}/administrativeRoles"
expect "02 POST: the body, by jq" "$(payload 1 | jq -c .)" '{"roleName":"example_role","isLimited":true,"isBounceAllowed":false,"menus":["Change Password"]}'
has "02 POST: prints the HTTP code" "HTTP 201"
ROLE_409=$(body role_409 '{"message":"Error validating request","validationErrors":["Administrative role with the same name already exist on the server."]}')
ST_POST=409 POST_BODY="${ROLE_409}" run "${F}/02.administrativeRoles_POST.sh"
expect "02 POST: a role that exists is exit 1" "${RC}" "1"
has "02 POST: with the reason" "Administrative role with the same name already exist on the server."

run "${F}/06.administrativeRoles_name_PATCH.sh" "Audit Log"
expect "06 PATCH: one PATCH of example_role" "${RC}:$(calls)" "0:PATCH ${BASE}/administrativeRoles/example_role"
expect "06 PATCH: the menu goes to the end of the list" "$(payload 1 | jq -c .)" '[{"op":"add","path":"/menus/-","value":"Audit Log"}]'
ROLE_400=$(body role_400 '{"message":"Error validating request","validationErrors":["List contains unsupported menu."]}')
ST_PATCH=400 ERR_BODY="${ROLE_400}" run "${F}/06.administrativeRoles_name_PATCH.sh" Nonsense
expect "06 PATCH: a menu the server does not know is exit 1" "${RC}" "1"
has "06 PATCH: with the reason" "List contains unsupported menu."
run "${F}/06.administrativeRoles_name_PATCH.sh" "   "
expect "06 PATCH: a blank menu is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

ROLE=$(body role '{"roleName":"example_role","menus":["Change Password","Audit Log"]}')
HOLDERS=$(body holders '{"result":[{"loginName":"example_admin"},{"loginName":"other_admin"}]}')
RULES=$(rules "administrators?roleName" "${HOLDERS}" "administrativeRoles/" "${ROLE}")
RULES="${RULES}" run "${F}/07.administrativeRoles_name_DELETE.sh"
expect "07 DELETE: reads the role and who holds it, then deletes it" "${RC}:$(calls)" "0:GET ${BASE}/administrativeRoles/example_role
GET ${BASE}/administrators?roleName=example_role&fields=loginName
DELETE ${BASE}/administrativeRoles/example_role"
has "07 DELETE: says what it deletes" "Deleting the role example_role (menus: Change Password, Audit Log; held by: example_admin, other_admin)..."
has "07 DELETE: prints the HTTP code" "HTTP 204"
RULES="${RULES}" run "${F}/07.administrativeRoles_name_DELETE.sh" "Other role"
expect "07 DELETE: the target role goes in the query" "$(calls | tail -1)" "DELETE ${BASE}/administrativeRoles/example_role?targetRoleName=Other role"
has "07 DELETE: and is named in what it says" "moving its administrators to Other role..."
RULES="${RULES}" ST_DELETE=404 ERR_BODY="${REFUSAL}" run "${F}/07.administrativeRoles_name_DELETE.sh" Nobody
expect "07 DELETE: a delete the server refuses is exit 1" "${RC}" "1"
has "07 DELETE: with HTTP 404" "HTTP 404"
GET_BODY="${ROLE_409}" ST_GET=404 run "${F}/07.administrativeRoles_name_DELETE.sh"
expect "07 DELETE: a role that cannot be read is exit 1 and nothing is deleted" "${RC}:$(calls | grep -c DELETE)" "1:0"
run "${F}/07.administrativeRoles_name_DELETE.sh" a b
expect "07 DELETE: two arguments are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo
echo "=== 21.Administrators/02 to 07 ==="
F=21.Administrators
ADM=$(body adm '{"loginName":"example_admin","roleName":"example_role","parent":"apiadmin","locked":true,"administratorRights":{"x":true},"apiKeys":[],"metadata":{"links":{}},"passwordCredentials":{}}')

ADMIN_PASSWORD='p@ss "w0rd"' LOCATION=example_admin run "${F}/02.administrators_POST.sh"
expect "02 POST: one POST, exit 0" "${RC}:$(calls)" "0:POST ${BASE}/administrators"
expect "02 POST: the body, by jq: the password from the environment, whatever it holds" \
  "$(payload 1 | jq -c '[.loginName, .roleName, .parent, .localAuthentication, .passwordCredentials.password]')" '["example_admin","example_role","apiadmin",true,"p@ss \"w0rd\""]'
hasnt "02 POST: a password given is never printed" 'w0rd'
has "02 POST: prints the HTTP code" "HTTP 201"
ADMIN_PASSWORD= run "${F}/02.administrators_POST.sh"
GENERATED=$(printf '%s\n' "${OUT}" | sed -n 's/^The password of example_admin is \([^ ]*\) (generated.*/\1/p')
expect "02 POST: with no password given, one is generated and printed once, and it is the one sent" "$(payload 1 | jq -r .passwordCredentials.password)" "${GENERATED}"
expect "02 POST: the generated one is 4 fixed characters and 12 letters and digits" "$(printf '%s' "${GENERATED}" | grep -cE '^Ex1![A-Za-z0-9]{12}$')" "1"
expect "02 POST: there is no 'change_me' default in the file" "$(grep -c 'change_me' "${ADMIN_TREE}/${F}/02.administrators_POST.sh")" "0"
ADM_409=$(body adm_409 '{"message":"Error validating request","validationErrors":["Entry already exist."]}')
ST_POST=409 POST_BODY="${ADM_409}" ADMIN_PASSWORD=x run "${F}/02.administrators_POST.sh"
expect "02 POST: an administrator that exists is exit 1" "${RC}" "1"
has "02 POST: with the reason" "Entry already exist."
hasnt "02 POST: and no password is printed for a creation that failed" "generated"

run "${F}/03.administrators_name_HEAD.sh" "a b"
expect "03 HEAD: the name is encoded" "$(calls)" "HEAD ${BASE}/administrators/a%20b"
GET_BODY="${ADM}" run "${F}/04.administrators_name_GET.sh" "a b"
expect "04 GET: the name is encoded" "$(calls)" "GET ${BASE}/administrators/a%20b"

GET_BODY="${ADM}" run "${F}/05.administrators_name_PUT.sh" "a b"
expect "05 PUT: reads, then PUTs, by the encoded name" "${RC}:$(calls)" "0:GET ${BASE}/administrators/a%20b
PUT ${BASE}/administrators/a%20b"
expect "05 PUT: unlocked, without the read only parts" "$(payload 1 | jq -c '[.locked, has("metadata"), has("apiKeys")]')" '[false,false,false]'
GET_BODY="${ADM_409}" ST_GET=404 run "${F}/05.administrators_name_PUT.sh"
expect "05 PUT: an administrator that cannot be read is exit 1, no PUT" "${RC}:$(calls | grep -c PUT)" "1:0"
GET_BODY="${ADM}" ST_PUT=400 ERR_BODY="${REFUSAL}" run "${F}/05.administrators_name_PUT.sh"
expect "05 PUT: a PUT the server refuses is exit 1, with the reason" "${RC}:$(printf '%s' "${OUT}" | grep -c 'Some reason the server gives.')" "1:1"

run "${F}/06.administrators_name_PATCH.sh" "a b"
expect "06 PATCH: one PATCH, by the encoded name" "${RC}:$(calls)" "0:PATCH ${BASE}/administrators/a%20b"
expect "06 PATCH: locked, by jq" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/locked","value":true}]'
run "${F}/06.administrators_name_PATCH.sh" apiadmin
expect "06 PATCH: the administrator logged in as is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run "${F}/06.administrators_name_PATCH.sh" APIAdmin
expect "06 PATCH: whatever the case, nothing sent" "${RC}:$(ncalls)" "2:0"
ST_PATCH=404 ERR_BODY="${REFUSAL}" run "${F}/06.administrators_name_PATCH.sh"
expect "06 PATCH: a 404 is exit 1, with the reason" "${RC}:$(printf '%s' "${OUT}" | grep -c 'Some reason the server gives.')" "1:1"

echo "  -- 07 DELETE: never the administrator logged in as"
S=07.administrators_name_DELETE.sh
GET_BODY="${ADM}" run "${F}/${S}"
expect "07: bare, reads example_admin, then deletes it" "${RC}:$(calls)" "0:GET ${BASE}/administrators/example_admin
DELETE ${BASE}/administrators/example_admin"
has "07: says what it deletes" "Deleting the administrator example_admin (role example_role, created by apiadmin, locked true)..."
has "07: prints the HTTP code" "HTTP 204"
GET_BODY="${ADM}" run "${F}/${S}" apiadmin
expect "07: the administrator logged in as (apiadmin) is refused, exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "07: and it says why" "It is never deleted."
GET_BODY="${ADM}" run "${F}/${S}" ApiAdmin
expect "07: whatever the case" "${RC}:$(ncalls)" "2:0"
GET_BODY="${ADM}" run "${F}/${S}" "a b"
expect "07: any other name is encoded" "$(calls | tail -1)" "DELETE ${BASE}/administrators/a%20b"
GET_BODY="${ADM_409}" ST_GET=404 run "${F}/${S}" example_nobody
expect "07: an administrator that cannot be read is exit 1 and nothing is deleted" "${RC}:$(calls | grep -c DELETE)" "1:0"
GET_BODY="${ADM}" ST_DELETE=400 ERR_BODY=$(body adm_400 '{"message":"Error validating request","validationErrors":["Administrator cannot be deleted."]}') run "${F}/${S}"
expect "07: a delete the server refuses is exit 1" "${RC}" "1"
has "07: with the reason" "Administrator cannot be deleted."
GET_BODY="${ADM}" run "${F}/${S}" a b
expect "07: two arguments are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
GET_BODY=; POST_BODY=; RULES=

echo
echo "=== the bat twins ==="
# Every script of this sweep, by its folder and name
SWEEP=$(cat <<'LIST'
12.BusinessUnits/01.businessUnits_POST
13.Configurations/38.configurations_externalStores_POST
13.Configurations/39.configurations_externalStores_name_GET
13.Configurations/40.configurations_externalStores_name_PUT
13.Configurations/41.configurations_externalStores_name_PATCH
13.Configurations/42.configurations_externalStores_name_operations_POST_test
13.Configurations/43.configurations_externalStores_name_operations_POST_clearCache
13.Configurations/44.configurations_externalStores_name_DELETE
13.Configurations/45.configurations_storageProfiles_options_PUT_register
13.Configurations/46.configurations_storageProfiles_name_operations_POST_test
13.Configurations/47.configurations_storageProfiles_options_PUT_unregister
15.Transfers/01.transfers_operations_POST_pull
17.AccessPolicies/02.accessPolicies_POST
18.AccountSetup/02.accountSetup_name_GET
18.AccountSetup/04.accounts_name_DELETE
20.AdministrativeRoles/02.administrativeRoles_POST
20.AdministrativeRoles/06.administrativeRoles_name_PATCH
20.AdministrativeRoles/07.administrativeRoles_name_DELETE
21.Administrators/02.administrators_POST
21.Administrators/03.administrators_name_HEAD
21.Administrators/04.administrators_name_GET
21.Administrators/05.administrators_name_PUT
21.Administrators/06.administrators_name_PATCH
21.Administrators/07.administrators_name_DELETE
LIST
)
for entry in ${SWEEP}; do
    sh_file="${ADMIN_TREE}/${entry}.sh"
    bat_file="${BAT_TREE}/${entry}.bat"
    name=$(basename "${entry}")
    [ -f "${sh_file}" ] && [ -f "${bat_file}" ] || { fail "${name}: both twins exist"; continue; }
    # the same exit codes: a script that exits 2 before sending anything does so in both, and one that exits 1 on a refusal
    for pair in "2:EXIT /B 2" "1:EXIT /B 1"; do
        code="${pair%%:*}"; bat_text="${pair#*:}"
        in_sh=$(grep -cE "(^|[^A-Za-z_])exit ${code}([^0-9]|$)" "${sh_file}")
        in_bat=$(grep -ciE "${bat_text}" "${bat_file}")
        if { [ "${in_sh}" -gt 0 ] && [ "${in_bat}" -gt 0 ]; } || { [ "${in_sh}" -eq 0 ] && [ "${in_bat}" -eq 0 ]; }; then
            pass "${name}: bash and bat both have exit ${code}, or neither"
        else
            fail "${name}: exit ${code} is in only one of the twins (bash ${in_sh}, bat ${in_bat})"
        fi
    done
    # a write prints the HTTP code in both
    if grep -q '"HTTP %s' "${sh_file}" || grep -q "'HTTP %s" "${sh_file}"; then
        expect "${name}: the bat prints the HTTP code too" "$(grep -c 'echo HTTP %HTTP_CODE%' "${bat_file}" | grep -c '^[1-9]')" "1"
    fi
    # curl -w in a bat is %%{http_code}, and a FOR /F command is closed by one quote
    expect "${name}: the bat has no %{http_code} with a single %" "$(grep -cE '(^|[^%])%\{http_code\}' "${bat_file}")" "0"
    expect "${name}: the bat has no doubled quote closing a FOR /F command" "$(grep -cE "''\) DO" "${bat_file}")" "0"
done
# the typo was in these sixteen files of 13.Configurations: none of the bat files may have it
expect "no bat file anywhere closes a FOR /F command with two quotes" "$(grep -rlE "''\) DO" "${BAT_TREE}" | wc -l | tr -d ' ')" "0"
# no name goes raw into a URL in the scripts of this sweep
for entry in 13.Configurations/39.configurations_externalStores_name_GET 13.Configurations/40.configurations_externalStores_name_PUT \
             13.Configurations/41.configurations_externalStores_name_PATCH 13.Configurations/42.configurations_externalStores_name_operations_POST_test \
             13.Configurations/43.configurations_externalStores_name_operations_POST_clearCache 13.Configurations/44.configurations_externalStores_name_DELETE \
             13.Configurations/46.configurations_storageProfiles_name_operations_POST_test 18.AccountSetup/02.accountSetup_name_GET \
             21.Administrators/03.administrators_name_HEAD 21.Administrators/04.administrators_name_GET 21.Administrators/05.administrators_name_PUT \
             21.Administrators/06.administrators_name_PATCH 21.Administrators/07.administrators_name_DELETE; do
    raw=$(grep -cE '/(externalStores|storageProfiles|accountSetup|administrators)/\$\{(NAME|PROFILE|ACCOUNT|ADMIN)\}|/(externalStores|storageProfiles|accountSetup|administrators)/%(NAME|PROFILE|ACCOUNT|ADMIN)%' \
          "${ADMIN_TREE}/${entry}.sh" "${BAT_TREE}/${entry}.bat" | awk -F: '{s += $2} END {print s}')
    expect "$(basename "${entry}"): no name goes into the URL unencoded, in either twin" "${raw}" "0"
done

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_bash_admin_sweep_b: PASS"
else
    echo "test_bash_admin_sweep_b: FAIL"
fi
exit "${FAILED}"
