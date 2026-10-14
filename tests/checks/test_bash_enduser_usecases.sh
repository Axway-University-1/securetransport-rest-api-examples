#!/bin/bash
# ==============================================================================
# Run the EndUser use cases (EndUser/UseCases/*) against a stub curl, and check
# the calls each script makes.
#
# 01-authentication: Basic authentication on a call (-u, no cookie), a call with
# no credentials that must be refused with 401, the login that keeps a cookie jar
# and the csrfToken, the call with the cookie only, the csrfToken header, the
# recovery from an expired session, the logout that proves the old cookie is dead,
# and the cleanup. Each script's exit code is checked too, so a server answer the
# script does not expect must stop it.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"
UC_SRC="${REPO}/EndUser/UseCases/01-authentication"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_enduser_usecases"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"

# The use case sits two folders under EndUser/, next to "API 2.0/bash" with its settings
mkdir -p "${WORK}/tree/UseCases"
cp "${REPO}/EndUser/API 2.0/bash/set_variables.sh" "${WORK}/tree/API 2.0/bash/"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp -R "${UC_SRC}" "${WORK}/tree/UseCases/"
UC="${WORK}/tree/UseCases/01-authentication"
BASE="https://st.example.com:8444/api/v2.0"
echo '{"name":"john","type":"user"}' > "${WORK}/me.json"

# run SCRIPT: STATUS sets every answer, STATUS_GET only the GETs, CSRF a csrfToken header on the login
run() {
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/me.json" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" \
          STUB_CURL_CSRF="${CSRF:-}" STUB_CURL_PRINT_CODE=1 bash "./$1" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ncalls() { calls | wc -l | tr -d ' '; }

echo "=== 01 Basic authentication on one call ==="
run 01.basic_auth_GET_myself.sh
expect "01: one GET /myself" "$(calls)" "GET ${BASE}/myself"
has "01: sends the user and password with -u" "BASIC_AUTH: "
hasnt "01: and no cookie, there is no session" "COOKIE:"
has "01: prints who you are" "You are john (user)"
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
has "03: with the user and password" "BASIC_AUTH: "
has "03: writing the cookie jar of this use case, not myCookie.jar" "COOKIE_JAR_WRITE: ${UC}/session.cookie.jar"
expect "03: saves the csrfToken" "$(cat "${UC}/state.local.csrf")" "tok123"
expect "03: exit 0" "${RC}" "0"
STATUS=401 run 03.session_login_POST.sh
expect "03: a refused login leaves no jar and exits 1" "${RC}:$([ -f "${UC}/session.cookie.jar" ] && echo jar || echo none)" "1:none"

echo "=== 04 the cookie, no password ==="
rm -f "${UC}/session.cookie.jar"
run 04.session_cookie_GET_myself.sh
expect "04: with no session it says to run 03 and exits 2, sending nothing" "${RC}:$(ncalls)" "2:0"
touch "${UC}/session.cookie.jar"
run 04.session_cookie_GET_myself.sh
expect "04: one GET /myself" "$(calls)" "GET ${BASE}/myself"
has "04: sends the cookie jar" "COOKIE: ${UC}/session.cookie.jar"
hasnt "04: and no password" "BASIC_AUTH:"
STATUS=401 run 04.session_cookie_GET_myself.sh
expect "04: a refused session exits 1" "${RC}" "1"

echo "=== 05 the csrfToken header ==="
echo tok123 > "${UC}/state.local.csrf"
run 05.session_csrf_header_GET_myself.sh
has "05: sends the csrfToken header" "HEADER: csrfToken: tok123"
has "05: and the cookie" "COOKIE: ${UC}/session.cookie.jar"
rm -f "${UC}/state.local.csrf"
run 05.session_csrf_header_GET_myself.sh
expect "05: with no saved token it sends nothing and exits 1" "${RC}:$(ncalls)" "1:0"

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
expect "99: removes the jar and the token" "$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo kept || echo gone)" "gone"
rm -f "${UC}/session.cookie.jar"
run 99.cleanup_DELETE.sh
expect "99: with no session it sends nothing" "$(ncalls)" "0"

# the stub answers 200 to a GET with no credentials, so 02 stops run_all: that shows the stop
run 00.run_all.sh
has "00: stops at the first failing script (02 got a 200)" "02.no_credentials_GET_myself failed."
has "00: and still runs the cleanup" "Cleaned up."
expect "00: exit 1" "${RC}" "1"
# a server that answers 401 to the no-credentials call (a GET) but 200 to the rest cannot be told apart by
# method for the GETs, so the full run is the lab check's job: here every script was run above on its own.

echo "=== The scripts say where they were copied from ==="
for f in 01 04 07 03; do
    s=$(ls "${UC_SRC}"/${f}.*.sh)
    ref=$(sed -n 's/^# - Copied from \(EndUser\/API 2.0\/bash\/[^ ,]*\).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    if [ -n "${ref}" ] && [ -f "${REPO}/${ref}" ]; then pass "$(basename "${s}"): copied from ${ref}, which exists"
    else fail "$(basename "${s}"): its 'Copied from' file does not exist (${ref})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_enduser_usecases: FAIL"; exit 1; fi
echo "test_bash_enduser_usecases: PASS"
