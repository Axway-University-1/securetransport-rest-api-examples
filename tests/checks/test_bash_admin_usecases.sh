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
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
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

# The real Admin set_variables.sh, with the test values as its local file; the use cases sit next to "API 2.0/bash"
cp "${REPO}/Admin/API 2.0/bash/set_variables.sh" "${WORK}/tree/API 2.0/bash/"
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
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${WORK}/me.json}" STUB_CURL_GET_RULES="${RULES:-}" \
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

echo "=== 99 cleanup and 00 run_all ==="
touch "${UC}/session.cookie.jar"; echo tok > "${UC}/state.local.csrf"
STATUS_GET=401 run 99.cleanup_DELETE.sh
expect "99: logs out, and removes the jar and the token" "$(calls | tr '\n' ' '):$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "DELETE ${BASE}/myself :gone"
rm -f "${UC}/session.cookie.jar"
run 99.cleanup_DELETE.sh
expect "99: with no session it sends nothing" "$(ncalls)" "0"
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

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}"/*/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    refs=$(sed -n 's/^# - Copied from \(Admin\/API 2.0\/bash\/[^ ,]*\).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "$(dirname "${s}")")/$(basename "${s}")"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecases: FAIL"; exit 1; fi
echo "test_bash_admin_usecases: PASS"
