#!/bin/bash
# ==============================================================================
# Run the Admin use cases (Admin/UseCases/*) against a stub curl, and check the
# calls each script makes: method, URL and query, body, headers, the answers it
# acts on, and its exit code.
#
# 01-authentication: Basic authentication on one call (-u, no cookie), a call with
# no credentials that must be refused with 401, the login that keeps a cookie jar
# and the csrfToken, the call with the cookie only, a session write that carries
# the csrfToken header and changes nothing, the recovery from an expired session,
# the logout that proves the old cookie is dead, and the cleanup.
#
# 02-knowing-the-server: the read-only tour (version, daemons, servers, a paged
# list, a setting among a thousand, login and maintenance settings, sessions),
# each starting with the check for an active session (st_session in
# UseCases/session.sh: a jar that is missing or refused is a login).
#
# 03-onboard-a-user-account: the account made (HEAD first, then a POST with the body of a user account and
# a user id that is the same for the same name), read back, changed with a JSON Patch, logged in to on the End
# User API (and refused with a wrong password), used (a folder, a file), emptied and deleted, the cleanup twice,
# and run_all stopping at a failing step, still cleaning up.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecases"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasre() { if printf '%s\n' "${OUT}" | grep -qE -- "$2"; then pass "$1"; else fail "$1  (nothing like '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

# the stub, behind the wrapper that answers each method with its own status
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"

# The test values as the settings file; the use cases sit next to "API 2.0/bash"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp -R "${UC_ROOT}/." "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
ME='{"loginName":"admin","roleName":"Master Administrator","isLimited":false,"preferredFileTrackingColumns":{"viewAccount":true,"viewDirection":true}}'
echo "${ME}" > "${WORK}/me.json"

# uc NAME: work in that use case. urun SCRIPT: run it with a session jar in place (the stub writes none);
# run SCRIPT leaves the jar as it is. GET_BODY, RULES and the STUB_STATUS_<METHOD> variables set the answers.
uc() { UC="${WORK}/tree/UseCases/$1"; }
run() {
    local rel="$1"; shift
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/me.json}" STUB_CURL_GET_RULES="${RULES:-}" STUB_CURL_POST_BODY="${POST_BODY:-}" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_CSRF="${CSRF:-}" \
          STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
urun() { touch "${UC}/session.cookie.jar"; run "$@"; }
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }
ncalls() { calls | wc -l | tr -d ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
headers() { printf '%s\n' "${OUT}" | sed -n 's/^HEADER: //p'; }
# hdrs_of METHOD: the headers of the call with that method (they are printed before its METHOD line)
hdrs_of() { printf '%s\n' "${OUT}" | awk -v M="$1" '/^HEADER:/ {b = b $0 "\n"} /^METHOD:/ {if ($2 == M) r = b; b = ""} END {printf "%s", r}' | sed 's/^HEADER: //'; }

echo "=== 01 Basic authentication on one call ==="
uc 01-authentication
run 01.basic_auth_GET_myself.sh
expect "01: one GET /myself" "$(calls)" "GET ${BASE}/myself"
has "01: sends the user and password with -u" "BASIC_AUTH: apiadmin:s3cret"
hasnt "01: and no cookie, there is no session" "COOKIE:"
has "01: prints who you are" "You are admin, role Master Administrator"
expect "01: exit 0" "${RC}" "0"
STATUS=401 run 01.basic_auth_GET_myself.sh
expect "01: a refused password stops it (exit 1)" "${RC}" "1"

echo "=== 02 no credentials ==="
STATUS=401 run 02.no_credentials_GET_myself.sh
expect "02: one GET /myself" "$(calls)" "GET ${BASE}/myself"
hasnt "02: with neither -u nor a cookie" "BASIC_AUTH:"
expect "02: 401 is the expected answer (exit 0)" "${RC}" "0"
STATUS=200 run 02.no_credentials_GET_myself.sh
expect "02: a 200 is not (exit 1)" "${RC}" "1"

echo "=== 03 login: the session and the csrfToken ==="
rm -f "${UC}"/session.cookie.jar "${UC}"/state.local.csrf
CSRF=tok123 run 03.session_login_POST.sh
expect "03: one POST /myself" "$(calls)" "POST ${BASE}/myself"
has "03: with the user and password" "BASIC_AUTH: apiadmin:s3cret"
hasre "03: writing the cookie jar of this use case" "^COOKIE_JAR_WRITE: .*/01-authentication/session\\.cookie\\.jar$"
expect "03: saves the csrfToken" "$(cat "${UC}/state.local.csrf")" "tok123"
expect "03: exit 0" "${RC}" "0"
STATUS=401 run 03.session_login_POST.sh
expect "03: a refused login leaves no jar and exits 1" "${RC}:$([ -f "${UC}/session.cookie.jar" ] && echo jar || echo none)" "1:none"

echo "=== 04 the cookie, no password ==="
rm -f "${UC}/session.cookie.jar"
run 04.session_cookie_GET_myself.sh
expect "04: with no session it says to run 03 and exits 2, sending nothing" "${RC}:$(ncalls)" "2:0"
urun 04.session_cookie_GET_myself.sh
expect "04: one GET /myself" "$(calls)" "GET ${BASE}/myself"
hasre "04: sends the cookie jar" "^COOKIE: .*/01-authentication/session\\.cookie\\.jar$"
hasnt "04: and no password" "BASIC_AUTH:"
STATUS=401 urun 04.session_cookie_GET_myself.sh
expect "04: a refused session exits 1" "${RC}" "1"

echo "=== 05 a write with the csrfToken header ==="
echo tok123 > "${UC}/state.local.csrf"
STUB_STATUS_PATCH=204 urun 05.session_csrf_header_PATCH_myself.sh
expect "05: asks about the option, reads, PATCHes, reads again" "$(calls | tr '\n' ' ')" \
  "GET ${BASE}/configurations/options?name=Webservices.Admin.CsrfToken.enabled GET ${BASE}/myself PATCH ${BASE}/myself GET ${BASE}/myself "
has "05: the PATCH sends the csrfToken header" "HEADER: csrfToken: tok123"
expect "05: with the value it already has" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/preferredFileTrackingColumns","value":{"viewAccount":true,"viewDirection":true}}]'
has "05: and says it is unchanged" "Unchanged, as it should be."
expect "05: exit 0" "${RC}" "0"
STUB_STATUS_PATCH=403 urun 05.session_csrf_header_PATCH_myself.sh
expect "05: a refused write is exit 1" "${RC}" "1"
GET_BODY="$(body nocols '{"loginName":"admin"}')" urun 05.session_csrf_header_PATCH_myself.sh
expect "05: an answer with no columns to patch sends no PATCH (exit 1)" "$(calls | grep -c PATCH):${RC}" "0:1"
rm -f "${UC}/state.local.csrf"
urun 05.session_csrf_header_PATCH_myself.sh
expect "05: with no saved token it sends nothing and exits 1" "${RC}:$(ncalls)" "1:0"
rm -f "${UC}/session.cookie.jar"
run 05.session_csrf_header_PATCH_myself.sh
expect "05: with no session it says to run 03 and exits 2" "${RC}:$(ncalls)" "2:0"

echo "=== 06 an expired session, then a new login ==="
STATUS_GET=401 run 06.session_expired_recovery.sh
expect "06: the stale call, then the login, then the call with the new session" \
  "$(calls | tr '\n' ' ')" "GET ${BASE}/myself POST ${BASE}/myself GET ${BASE}/myself "
has "06: says the session is lost" "The session is lost. Logging in again..."
STATUS_GET=403 run 06.session_expired_recovery.sh
has "06: a 403 is a lost session too" "The session is lost"
STATUS_GET=500 run 06.session_expired_recovery.sh
expect "06: a 500 is not a lost session: no login, exit 1" "${RC}:$(ncalls)" "1:1"

echo "=== 07 logout, then the old cookie is refused ==="
touch "${UC}/session.cookie.jar"; echo tok > "${UC}/state.local.csrf"
STATUS_GET=401 run 07.logout_DELETE.sh
expect "07: DELETE /myself, then a GET with the old cookie" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/myself GET ${BASE}/myself "
has "07: the logout carries the csrfToken" "HEADER: csrfToken: tok"
expect "07: the 401 proves it, exit 0, jar and token removed" "${RC}:$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "0:gone"
touch "${UC}/session.cookie.jar"
STATUS_GET=200 run 07.logout_DELETE.sh
expect "07: an old cookie that still works is reported (exit 1)" "${RC}" "1"
rm -f "${UC}/session.cookie.jar"
run 07.logout_DELETE.sh
expect "07: with no session it says to run 03 and exits 2" "${RC}:$(ncalls)" "2:0"

echo "=== 08 an API key ==="
KEYBODY=$(body newkey '{"id":"k1","key":"secret-key-1","expiresAt":"Tue, 20 Oct 2026 15:35:38 +0300","permissions":["read"]}')
rm -f "${UC}"/state.local.apikey "${UC}"/state.local.apikey_id
STATUS=201 POST_BODY="${KEYBODY}" run 08.apikey_POST.sh
expect "08: one POST to the administrator's api-keys" "$(calls)" "POST ${BASE}/administrators/apiadmin/api-keys"
has "08: with the user and password: a key cannot make its own" "BASIC_AUTH: apiadmin:s3cret"
expect "08: a day, read only" "$(payload 1 | jq -c '[.validityDays, .permissions]')" '[1,["read"]]'
expect "08: the key and its id are kept" "$(cat "${UC}/state.local.apikey"):$(cat "${UC}/state.local.apikey_id")" "secret-key-1:k1"
expect "08: the key file is for its owner only" "$(ls -l "${UC}/state.local.apikey" | cut -c1-10)" "-rw-------"
hasnt "08: the key is not printed" "secret-key-1"
has "08: the id and the validity are" "Key id k1"
expect "08: exit 0" "${RC}" "0"
STATUS=201 POST_BODY="${KEYBODY}" run 08.apikey_POST.sh
expect "08: a key left from an earlier run is revoked first (by its id, and shown dead), then a new one is made" "$(calls | tr '\n' ' ')" \
  "DELETE ${BASE}/administrators/apiadmin/api-keys/k1 GET ${BASE}/myself POST ${BASE}/administrators/apiadmin/api-keys "
rm -f "${UC}"/state.local.apikey "${UC}"/state.local.apikey_id
STATUS=409 run 08.apikey_POST.sh
expect "08: a third key is 409: exit 1, saved nothing, says to revoke one" "${RC}:$([ -e "${UC}/state.local.apikey" ] && echo kept || echo none)" "1:none"
has "08: and says what to do" "at most 2 API keys"
STATUS=201 POST_BODY="${WORK}/me.json" run 08.apikey_POST.sh
expect "08: an answer with no key is exit 1" "${RC}:$([ -e "${UC}/state.local.apikey" ] && echo kept || echo none)" "1:none"

echo "=== 09 the key and nothing else ==="
rm -f "${UC}"/state.local.apikey "${UC}"/state.local.apikey_id
run 09.apikey_GET_myself.sh
expect "09: with no key it says to run 08 and exits 2, sending nothing" "${RC}:$(ncalls)" "2:0"
printf '%s' secret-key-1 > "${UC}/state.local.apikey"
STUB_STATUS_PATCH=403 run 09.apikey_GET_myself.sh
expect "09: a read, then a write that the read-only key must be refused" "$(calls | tr '\n' ' ')" "GET ${BASE}/myself PATCH ${BASE}/myself "
expect "09: both calls carry the key" "$(headers | grep -c '^SECURETRANSPORT-API-KEY: secret-key-1$')" "2"
hasnt "09: and neither a password" "BASIC_AUTH:"
hasnt "09: nor a cookie" "COOKIE:"
hasnt "09: nor a csrfToken" "csrfToken"
has "09: prints who you are" "You are admin, role Master Administrator"
expect "09: exit 0" "${RC}" "0"
STUB_STATUS_PATCH=204 run 09.apikey_GET_myself.sh
expect "09: a write that the read-only key is allowed is a failure (exit 1)" "${RC}" "1"
STATUS_GET=401 run 09.apikey_GET_myself.sh
expect "09: a read that is refused stops it (exit 1), before the write" "${RC}:$(calls | grep -c PATCH)" "1:0"

echo "=== 10 revoke it ==="
rm -f "${UC}"/state.local.apikey "${UC}"/state.local.apikey_id
run 10.apikey_DELETE.sh
expect "10: with no key it says so and exits 2, sending nothing" "${RC}:$(ncalls)" "2:0"
printf '%s' secret-key-1 > "${UC}/state.local.apikey"; printf '%s' k1 > "${UC}/state.local.apikey_id"
STATUS_GET=401 STUB_STATUS_DELETE=204 run 10.apikey_DELETE.sh
expect "10: DELETE of that key's id, then the revoked key is tried" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/administrators/apiadmin/api-keys/k1 GET ${BASE}/myself "
has "10: the revoke is made with the password" "BASIC_AUTH: apiadmin:s3cret"
has "10: and the key is tried alone" "HEADER: SECURETRANSPORT-API-KEY: secret-key-1"
expect "10: a 401 proves it, exit 0, both files removed" "${RC}:$([ -e "${UC}/state.local.apikey" ] || [ -e "${UC}/state.local.apikey_id" ] && echo kept || echo gone)" "0:gone"
printf '%s' secret-key-1 > "${UC}/state.local.apikey"; printf '%s' k1 > "${UC}/state.local.apikey_id"
STATUS_GET=200 STUB_STATUS_DELETE=204 run 10.apikey_DELETE.sh
expect "10: a revoked key that still works is exit 1" "${RC}" "1"
printf '%s' secret-key-1 > "${UC}/state.local.apikey"; printf '%s' k1 > "${UC}/state.local.apikey_id"
STUB_STATUS_DELETE=404 run 10.apikey_DELETE.sh
expect "10: a revoke that is refused is exit 1, and the files stay (so it can be tried again)" "${RC}:$([ -e "${UC}/state.local.apikey_id" ] && echo kept || echo gone)" "1:kept"
rm -f "${UC}"/state.local.apikey "${UC}"/state.local.apikey_id

echo "=== 99 cleanup and 00 run_all ==="
touch "${UC}/session.cookie.jar"; echo tok > "${UC}/state.local.csrf"
STATUS_GET=401 run 99.cleanup_DELETE.sh
expect "99: logs out, and removes the jar and the token" "$(calls | tr '\n' ' '):$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "DELETE ${BASE}/myself :gone"
rm -f "${UC}/session.cookie.jar"
run 99.cleanup_DELETE.sh
expect "99: with no session it sends nothing" "$(ncalls)" "0"
printf '%s' k9 > "${UC}/state.local.apikey_id"; printf '%s' key9 > "${UC}/state.local.apikey"
STATUS_GET=401 STUB_STATUS_DELETE=204 run 99.cleanup_DELETE.sh
expect "99: a key of this use case that is left is revoked by its id, and its files go" "$(calls | head -1):$([ -e "${UC}/state.local.apikey" ] || [ -e "${UC}/state.local.apikey_id" ] && echo kept || echo gone)" "DELETE ${BASE}/administrators/apiadmin/api-keys/k9:gone"
run 00.run_all.sh
has "00: stops at the first failing script (02 got a 200)" "02.no_credentials_GET_myself failed."
has "00: and still runs the cleanup" "Cleaned up."
expect "00: exit 1" "${RC}" "1"

echo "=== 02-knowing-the-server: every script starts with the check for a session ==="
uc 02-knowing-the-server
for rel in 01.version_GET.sh 03.servers_GET.sh 07.sessions_GET.sh; do
    rm -f "${UC}/session.cookie.jar"
    run "${rel}"
    expect "${rel}: with no jar it logs in first (POST /myself with the user and password), then goes on" "$(calls | head -1)" "POST ${BASE}/myself"
    has "${rel}: and says so" "There is no session yet. Logging in..."
done
STATUS_GET=401 urun 01.version_GET.sh
has "a session the server refuses (401) is a login too" "The session is no longer active (HTTP 401). Logging in..."
STATUS_GET=500 urun 01.version_GET.sh
expect "a 500 is not a lost session: no login" "$(calls | grep -c POST):${RC}" "0:1"
rm -f "${UC}/session.cookie.jar"
STUB_STATUS_POST=401 run 01.version_GET.sh
expect "a login that fails stops the script (exit 1) before its own call" "${RC}:$(ncalls)" "1:1"

echo "=== 02-knowing-the-server ==="
GET_BODY="$(body version '{"serverType":"ST-Core-Server","version":"5.5-20260924","build":"1813","updateLevel":"5.5_UPDATE-20260924","os":"Linux","osDistribution":"RHEL 9.5","user":"root","dockerMode":false,"plugins":[{"name":"s3","type":"TRANSFER_SITE"},{"name":"smb","type":"TRANSFER_SITE"},{"name":"oauth","type":"AUTHENTICATION"}]}')" urun 01.version_GET.sh
expect "01: GET /version" "$(ucalls)" "GET ${BASE}/version"
has "01: the release and build" "Release: 5.5-20260924 (build 1813)"
has "01: counts the plugins" "Plugins: 3"
has "01: groups them by type" "  TRANSFER_SITE: s3, smb"
GET_BODY="$(body daemons '{"ftpStatus":"Running","as2Status":"Not running"}')" urun 02.daemons_GET.sh
expect "02: GET /daemons" "$(ucalls)" "GET ${BASE}/daemons"
has "02: one line per daemon, without the word Status" "  as2	Not running"
GET_BODY="$(body servers '{"resultSet":{"returnCount":2,"totalCount":2},"result":[{"protocol":"ssh","serverName":"Ssh Default","isActive":true,"sslListenerPort":22},{"protocol":"http","serverName":"Http Default","isActive":false}]}')" urun 03.servers_GET.sh
expect "03: GET /servers" "$(ucalls)" "GET ${BASE}/servers"
has "03: counts them" "Servers: 2 of 2"
has "03: one line each" "  ssh	active	Ssh Default	ssl port 22"
has "03: a null port prints a dash" "ssl port -"
GET_BODY="$(body users '{"resultSet":{"returnCount":5,"totalCount":539},"result":[{"name":"ann","lastAccessTime":"October 8, 2026, 9:36 AM"}]}')" urun 04.statisticsSummary_activeUsers_GET.sh
expect "04: two pages of 5, each with limit and offset" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/statisticsSummary/activeUsers?limit=5&offset=0 GET ${BASE}/statisticsSummary/activeUsers?limit=5&offset=5 "
has "04: says how many there are in all" "(of 539 in all)"
expect "04: exit 0" "${RC}" "0"
GET_BODY="$(body users1 '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"name":"ann","lastAccessTime":"x"}]}')" urun 04.statisticsSummary_activeUsers_GET.sh
expect "04: stops after the first page when that was all there is" "$(ucalls | wc -l | tr -d ' '):${RC}" "1:0"
STATUS_GET=500 urun 04.statisticsSummary_activeUsers_GET.sh
expect "04: an error is exit 1" "${RC}" "1"
OPT='{"resultSet":{"returnCount":1,"totalCount":6},"result":[{"name":"Webservices.Admin.CsrfToken.enabled","values":["true"]}]}'
GET_BODY="$(body opts "${OPT}")" urun 05.configurations_options_GET.sh
expect "05: counts all, the modified ones, the pattern, then lists the pattern" "$(ucalls | tr '\n' ' ')" \
  "GET ${BASE}/configurations/options?limit=1 GET ${BASE}/configurations/options?isModified=true&limit=1 GET ${BASE}/configurations/options?name=Webservices.Admin.*&limit=1 GET ${BASE}/configurations/options?name=Webservices.Admin.*&limit=10 "
has "05: prints a name and its value" "  Webservices.Admin.CsrfToken.enabled = true"
GET_BODY="$(body opts "${OPT}")" urun 05.configurations_options_GET.sh 'Mail*'
has "05: a pattern given is the one searched" "?name=Mail*&limit=10"
GET_BODY="$(body login '{"requirePassword":"optional","userSSO":"disabled","adminSSO":"disabled","ldapOption":"disabled","zduMaintenanceMode":"enabled"}')" urun 06.configurations_settings_GET.sh
expect "06: loginSettings, then maintenance" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/configurations/loginSettings GET ${BASE}/configurations/maintenance "
has "06: the login settings, narrowed" "  user password:       optional"
has "06: the maintenance mode" "Maintenance mode: enabled"
GET_BODY="$(body sessions '[{"userName":"john","host":"10.0.0.1","protocol":"HTTP","sessionCreationTime":"Thu"},{"userName":"ann","host":"10.0.0.2","protocol":"SSH","sessionCreationTime":"Fri"}]')" urun 07.sessions_GET.sh
expect "07: GET /sessions" "$(ucalls)" "GET ${BASE}/sessions"
has "07: counts them" "Open sessions: 2"
has "07: by protocol" "  SSH: 1"
has "07: and each one" "  ann  from 10.0.0.2  SSH  since Fri"
GET_BODY="$(body nosessions '[]')" urun 07.sessions_GET.sh
has "07: an empty list is not an error" "Open sessions: 0"
expect "07: exit 0" "${RC}" "0"
touch "${UC}/session.cookie.jar"
run 99.cleanup_DELETE.sh
expect "99: logs out" "$(calls | tr '\n' ' ')" "DELETE ${BASE}/myself "
RULESET=$(rules /version "${WORK}/version.json" /daemons "${WORK}/daemons.json" /servers "${WORK}/servers.json" activeUsers "${WORK}/users.json" configurations/options "${WORK}/opts.json" loginSettings "${WORK}/login.json" maintenance "${WORK}/login.json" /sessions "${WORK}/sessions.json")
RULES="${RULESET}" urun 00.run_all.sh
expect "00: runs the seven scripts, then 99, and exits 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== ')" "0:8"

echo "=== 03-onboard-a-user-account ==="
uc 03-onboard-a-user-account
EUBASE="https://st.example.com:8443/api/v2.0"
PWFILE="${UC}/state.local.password"
rm -f "${PWFILE}"
# 01: the account is looked for, then made
STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 STUB_CURL_LOCATION_ID=abc123 urun 01.accounts_POST.sh
expect "01: HEAD the name, then POST /accounts" "${RC}:$(ucalls | tr '\n' ' ')" "0:HEAD ${BASE}/accounts/example_onboard POST ${BASE}/accounts "
expect "01: a user account with a home folder, an email and the same uid and gid" \
  "$(payload 1 | jq -c '[.name, .type, .homeFolder, .contact.email, (.uid == .gid), (.uid | tonumber >= 50000 and tonumber <= 59999)]')" '["example_onboard","user","/home/example_onboard","example_onboard@example.com",true,true]'
expect "01: the password goes in user.passwordCredentials.password, and it is not empty" "$(payload 1 | jq -r '.user.passwordCredentials.password | length > 8')" "true"
expect "01: the name goes in user.name too" "$(payload 1 | jq -r .user.name)" "example_onboard"
expect "01: the POST carries accept, Referer, the content type and the csrfToken" "$(hdrs_of POST | grep -cE '^(Referer: |Content-Type: application/json|accept: \*/\*|csrfToken:)')" "4"
has "01: says what it makes" "Creating the account example_onboard (home /home/example_onboard, user id "
has "01: shows the answer's code and where the account is" "HTTP 201"
has "01: and says where the password went" "The password is in state.local.password"
expect "01: the password is kept in state.local.password, and it is the one that was sent" "$(cat "${PWFILE}")" "$(payload 1 | jq -r .user.passwordCredentials.password)"
FIRST_UID=$(payload 1 | jq -r .uid)
rm -f "${PWFILE}"
STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 urun 01.accounts_POST.sh example_onboard
expect "01: the same name has the same user id every time" "$(payload 1 | jq -r .uid)" "${FIRST_UID}"
STUB_STATUS_HEAD=404 STUB_STATUS_POST=201 urun 01.accounts_POST.sh example_onboard_other ann@corp.example
expect "01: another name has its own folder, id and email" "$(payload 1 | jq -c '[.name, .homeFolder, .contact.email, (.uid != "'"${FIRST_UID}"'")]')" '["example_onboard_other","/home/example_onboard_other","ann@corp.example",true]'
rm -f "${PWFILE}"
STUB_STATUS_HEAD=200 urun 01.accounts_POST.sh
expect "01: an account that exists is not made again: exit 1, no POST" "${RC}:$(ucalls | grep -c POST)" "1:0"
has "01: and it says so, and how to remove it" "The account example_onboard already exists. Nothing was created. Remove it with 99.cleanup_DELETE.sh example_onboard"
expect "01: nothing is saved for an account that was not made" "$([ -e "${PWFILE}" ] && echo kept || echo none)" "none"
STUB_STATUS_HEAD=500 urun 01.accounts_POST.sh
expect "01: a HEAD that is not 200 or 404 is exit 1, nothing made" "${RC}:$(ucalls | grep -c POST)" "1:0"
has "01: and says it could not tell" "Could not tell whether the account example_onboard exists (HTTP 500). Nothing was created."
STUB_STATUS_HEAD=404 STUB_STATUS_POST=400 urun 01.accounts_POST.sh
expect "01: a refused create is exit 1, and no password is kept" "${RC}:$([ -e "${PWFILE}" ] && echo kept || echo none)" "1:none"
urun 01.accounts_POST.sh real_account
expect "01: a name that does not start with example_ is exit 2, and nothing at all is sent (not even the login)" "${RC}:$(ncalls)" "2:0"
has "01: with the reason" "NAME is 'real_account': it must start with example_"
has "01: and the usage" "Usage: ./01.accounts_POST.sh [NAME] [EMAIL]"
urun 01.accounts_POST.sh example_a b@c.d extra
expect "01: three parameters is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: and it says how many were given and how many are taken" "3 parameters were given, and at most 2 are taken: NAME and EMAIL."

# 02: read back
ACCT='{"name":"example_onboard","type":"user","homeFolder":"/home/example_onboard","disabled":false,"contact":{"email":"example_onboard@example.com"},"accountCreationDate":1793184896737,"transfersWebServiceAllowed":false,"user":{"locked":false,"failedAuthMaximum":3,"secretQuestion":{"secretQuestion":null},"passwordCredentials":{"password":null}}}'
GET_BODY="$(body acct "${ACCT}")" STUB_STATUS_HEAD=200 urun 02.accounts_GET.sh
expect "02: HEAD, then GET of the account" "${RC}:$(ucalls | tr '\n' ' ')" "0:HEAD ${BASE}/accounts/example_onboard GET ${BASE}/accounts/example_onboard "
has "02: shows the home folder" "homeFolder                  /home/example_onboard"
has "02: shows the email and what it is for" "needed to share folders"
has "02: shows when the account was made, in UTC" "accountCreationDate         2026-10-28T"
has "02: says that a null secret question is no secret question" "secret question set         no"
has "02: shows the lock and the number of wrong passwords that locks" "true after 3 wrong passwords"
has "02: says the password is never returned" "the password is never returned"
GET_BODY="$(body acct_sq "$(echo "${ACCT}" | jq -c '.user.secretQuestion.secretQuestion = "Dog?"')")" STUB_STATUS_HEAD=200 urun 02.accounts_GET.sh
has "02: and yes when it is set" "secret question set         yes"
STUB_STATUS_HEAD=404 urun 02.accounts_GET.sh
expect "02: no account is exit 1, and no GET" "${RC}:$(ucalls | grep -c GET)" "1:0"
has "02: it says to run 01 first" "There is no account example_onboard. Run 01.accounts_POST.sh first."
GET_BODY="$(body acct)" STUB_STATUS_HEAD=200 STUB_STATUS_GET=500 urun 02.accounts_GET.sh
expect "02: a GET that fails is exit 1" "${RC}" "1"
urun 02.accounts_GET.sh not_ours
expect "02: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 03: one change
GET_BODY="$(body acct_new "$(echo "${ACCT}" | jq -c '.contact.email = "example_onboard_changed@example.com"')")" STUB_STATUS_PATCH=204 urun 03.accounts_PATCH.sh
expect "03: reads, PATCHes, reads again" "${RC}:$(ucalls | tr '\n' ' ')" "0:GET ${BASE}/accounts/example_onboard PATCH ${BASE}/accounts/example_onboard GET ${BASE}/accounts/example_onboard "
expect "03: the patch replaces /contact/email" "$(payload 1 | jq -c .)" '[{"op":"replace","path":"/contact/email","value":"example_onboard_changed@example.com"}]'
expect "03: the PATCH carries accept, Referer, the content type and the csrfToken" "$(hdrs_of PATCH | grep -cE '^(Referer: |Content-Type: application/json|accept: application/json|csrfToken:)')" "4"
has "03: says that nothing else was touched" "Changed, and nothing else was touched."
GET_BODY="$(body acct_new)" STUB_STATUS_PATCH=204 urun 03.accounts_PATCH.sh example_onboard ann@corp.example
expect "03: a new address given is the one sent" "$(payload 1 | jq -r '.[0].value')" "ann@corp.example"
has "03: and an address that is not the one read back is said and is exit 1 (the change did not take)" "the change did not take."
expect "03: ... exit 1" "${RC}" "1"
GET_BODY="$(body acct_new)" STUB_STATUS_PATCH=400 urun 03.accounts_PATCH.sh
expect "03: a refused PATCH is exit 1" "${RC}" "1"
has "03: and says the address was not changed" "The server did not accept the change. The address was not changed."
urun 03.accounts_PATCH.sh not_ours
expect "03: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 04: the user logs in on the End User API
rm -f "${PWFILE}"
run 04.enduser_login_GET.sh
expect "04: with no state.local.password it says to run 01 first, exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "04: and says why" "There is no state.local.password: run 01.accounts_POST.sh first"
printf '%s' 'pw-secret-1' > "${PWFILE}"
GET_BODY="$(body me '{"name":"example_onboard","type":"user","sharingAllowed":true}')" STUB_STATUS_GET_SEQ="200 401" STUB_COUNTER="${WORK}/ctr04" run 04.enduser_login_GET.sh
rm -f "${WORK}"/ctr04.*
expect "04: two GETs of /myself on the End User port" "${RC}:$(calls | tr '\n' ' ')" "0:GET ${EUBASE}/myself GET ${EUBASE}/myself "
has "04: the first is the user with the password of state.local.password" "BASIC_AUTH: example_onboard:pw-secret-1"
has "04: the second is a wrong password, on purpose" "BASIC_AUTH: example_onboard:not-the-password"
has "04: says who logged in, and whether sharing is allowed" "Logged in as example_onboard (user); sharingAllowed: true"
has "04: says that the wrong password was refused, the same as an unknown user" "Refused, as it should be. The answer is the same for a wrong password and for a user that does not exist."
GET_BODY="$(body me)" STUB_STATUS_GET=401 run 04.enduser_login_GET.sh
expect "04: a login that fails is exit 1" "${RC}" "1"
has "04: and says the account could not log in" "The new account could not log in."
GET_BODY="$(body me)" STUB_STATUS_GET=000 run 04.enduser_login_GET.sh
expect "04: no answer at all is exit 1" "${RC}" "1"
has "04: and names the setting for the port" "set ST_ENDUSER_PORT in set_variables.local.sh"
GET_BODY="$(body me)" run 04.enduser_login_GET.sh
has "04: a wrong password that is accepted (200) is said, and is exit 1" "A wrong password was answered 200, not 401."
expect "04: ... exit 1" "${RC}" "1"
run 04.enduser_login_GET.sh not_ours
expect "04: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 05: the home folder is used
GET_BODY="$(body files '{"files":[{"fileName":"hello.txt","size":30}]}')" STUB_STATUS_POST=201 run 05.enduser_home_POST.sh
expect "05: POST the folder, POST the file, GET the list" "${RC}:$(calls | tr '\n' ' ')" "0:POST ${EUBASE}/files/welcome POST ${EUBASE}/files/welcome GET ${EUBASE}/files/welcome "
expect "05: the folder body says that it is a directory" "$(payload 1 | jq -c '[.isDirectory, .isRegularFile]')" "[true,false]"
has "05: as the user, with the password" "BASIC_AUTH: example_onboard:pw-secret-1"
has "05: the file goes in as a form with the name hello.txt" "filename=hello.txt"
has "05: the list is shown" "  hello.txt	30 bytes"
STUB_STATUS_POST=403 run 05.enduser_home_POST.sh
expect "05: a 403 on the folder is exit 1, no upload" "${RC}:$(calls | grep -c POST)" "1:1"
has "05: and the message names the cause (a home owned by another user id)" "another user id, use another name"
STUB_STATUS_POST_SEQ="409 201" STUB_COUNTER="${WORK}/ctr05" GET_BODY="$(body files)" run 05.enduser_home_POST.sh
rm -f "${WORK}"/ctr05.*
expect "05: a folder that is already there (409) is not an error: the file is uploaded" "${RC}" "0"
has "05: and it says so" "The folder welcome is already there."
STUB_STATUS_POST_SEQ="201 500" STUB_COUNTER="${WORK}/ctr05b" GET_BODY="$(body files)" run 05.enduser_home_POST.sh
rm -f "${WORK}"/ctr05b.*
expect "05: an upload that fails is exit 1" "${RC}" "1"
has "05: and says the file was not uploaded" "The file was not uploaded."
rm -f "${PWFILE}"
run 05.enduser_home_POST.sh
expect "05: with no password file it says to run 01, exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 06: the home is emptied, then the account goes
printf '%s' 'pw-secret-1' > "${PWFILE}"
WEL="$(body welcome '{"files":[{"fileName":"hello.txt","isDirectory":false}]}')"
ROOT_LIST="$(body root '{"files":[{"fileName":"welcome","isDirectory":true}]}')"
LRULES="$(rules "${EUBASE}/files/welcome" "${WEL}" "${EUBASE}/files" "${ROOT_LIST}")"
RULES="${LRULES}" STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=204 STUB_STATUS_GET_SEQ="200 200 200 404" STUB_COUNTER="${WORK}/ctr06" urun 06.accounts_DELETE.sh
rm -f "${WORK}"/ctr06.*
expect "06: looks for the account, empties the home as the user, deletes the account, reads it" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:HEAD ${BASE}/accounts/example_onboard GET ${EUBASE}/files GET ${EUBASE}/files/welcome DELETE ${EUBASE}/files/welcome/hello.txt DELETE ${EUBASE}/files/welcome DELETE ${BASE}/accounts/example_onboard GET ${BASE}/accounts/example_onboard "
has "06: says how many entries it removed from the home (the file, then the folder)" "Emptied the home folder of example_onboard: 2 entries removed."
has "06: shows the DELETE answer and the read after it" "DELETE: HTTP 204"
has "06: and the 404" "GET: HTTP 404"
has "06: says that the home folder stays, with the user id" "Its home folder /home/example_onboard is not: it stays on the server with user id ${FIRST_UID}."
expect "06: the password file goes with the account" "$([ -e "${PWFILE}" ] && echo kept || echo gone)" "gone"
STUB_STATUS_HEAD=404 urun 06.accounts_DELETE.sh
expect "06: no account is exit 0 and no DELETE" "${RC}:$(ucalls | grep -c DELETE)" "0:0"
has "06: and it says there is nothing to delete" "There is no account example_onboard: nothing to delete."
STUB_STATUS_HEAD=500 urun 06.accounts_DELETE.sh
expect "06: a HEAD that is not 200 or 404 is exit 1, nothing deleted" "${RC}:$(ucalls | grep -c DELETE)" "1:0"
printf '%s' 'pw-secret-1' > "${PWFILE}"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=403 RULES="${LRULES}" urun 06.accounts_DELETE.sh
expect "06: a refused DELETE of the account is exit 1" "${RC}" "1"
has "06: and says the account was not deleted" "The account was not deleted."
rm -f "${PWFILE}"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=204 STUB_STATUS_GET_SEQ="404" STUB_COUNTER="${WORK}/ctr06b" urun 06.accounts_DELETE.sh
rm -f "${WORK}"/ctr06b.*
has "06: with no password file the home cannot be emptied, and it says so" "There is no state.local.password: the home folder cannot be emptied as the user, so its files stay."
expect "06: and the account is still deleted" "${RC}:$(ucalls | grep -c 'DELETE '"${BASE}"'/accounts')" "0:1"
printf '%s' 'pw-secret-1' > "${PWFILE}"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=204 STUB_STATUS_GET=200 RULES="${LRULES}" urun 06.accounts_DELETE.sh
expect "06: an account that is still there after the DELETE is exit 1" "${RC}" "1"
has "06: and says so" "The account is still there."
urun 06.accounts_DELETE.sh not_ours
expect "06: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 99: the cleanup, twice
printf '%s' 'pw-secret-1' > "${PWFILE}"; echo tok > "${UC}/state.local.csrf"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=204 RULES="${LRULES}" urun 99.cleanup_DELETE.sh
expect "99: the account is looked for, emptied, deleted, and the session ended" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:HEAD ${BASE}/accounts/example_onboard GET ${EUBASE}/files GET ${EUBASE}/files/welcome DELETE ${EUBASE}/files/welcome/hello.txt DELETE ${EUBASE}/files/welcome DELETE ${BASE}/accounts/example_onboard DELETE ${BASE}/myself "
has "99: says the account was deleted" "The account example_onboard was deleted."
expect "99: the state files and the jar are gone" "$([ -e "${PWFILE}" ] || [ -e "${UC}/state.local.csrf" ] || [ -e "${UC}/session.cookie.jar" ] && echo kept || echo gone)" "gone"
STUB_STATUS_HEAD=404 run 99.cleanup_DELETE.sh
expect "99: a second run, with nothing to remove, is exit 0 and deletes nothing" "${RC}:$(calls | grep -c DELETE)" "0:0"
has "99: and says there is nothing to delete" "There is no account example_onboard: nothing to delete."
has "99: and that it cleaned up" "Cleaned up."
printf '%s' 'pw-secret-1' > "${PWFILE}"
STUB_STATUS_HEAD=200 STUB_STATUS_DELETE=403 RULES="${LRULES}" urun 99.cleanup_DELETE.sh
expect "99: an account that cannot be deleted is exit 1, with the hint" "${RC}" "1"
has "99: names the account and the code" "The account example_onboard could not be deleted (HTTP 403): delete it by hand."
urun 99.cleanup_DELETE.sh not_ours
expect "99: a name that does not start with example_ is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

# 00: run_all
rm -f "${PWFILE}"
STUB_STATUS_HEAD=200 run 00.run_all.sh example_onboard_x
has "00: a step that fails stops it, by name (01 finds the account already there)" "01.accounts_POST failed."
has "00: and the cleanup still runs" "=== 99.cleanup_DELETE ==="
expect "00: exit 1, and no step after 01 ran" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== 02')" "1:0"
run 00.run_all.sh real_account
expect "00: a name that does not start with example_ stops it at once: exit 2, nothing sent, no cleanup" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c '99.cleanup')" "2:0:0"
has "00: with the usage" "Usage: ./00.run_all.sh [NAME] [EMAIL]"
run 00.run_all.sh example_a b@c.d extra
expect "00: three parameters is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm -f "${PWFILE}" "${UC}/state.local.csrf" "${UC}/session.cookie.jar"

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}"/*/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/API 2.0\/bash\/[^ ,]*).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "$(dirname "${s}")")/$(basename "${s}")"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecases: FAIL"; exit 1; fi
echo "test_bash_admin_usecases: PASS"
