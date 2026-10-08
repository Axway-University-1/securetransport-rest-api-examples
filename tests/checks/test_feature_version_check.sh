#!/bin/bash
# ==============================================================================
# Check Features/lib/st_feature_check.sh against a stub curl, then the other shared helpers in
# Features/lib (post_admin.sh, admin_calls.sh, enduser.sh, home_folder.sh) on their own.
#
# Every feature example starts with this check, so it must:
#   - let the example run on a server at or after the introducing version
#   - skip (exit 0, example never reached) on an older server
#   - stop with an error (exit 1) when the version cannot be read
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd .. && pwd)"

WORK="${TESTS_DIR}/output/feature_version_check"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl"
chmod +x "${WORK}/bin/curl"

# A stand-in feature example: the check, then a line proving the example ran
cat > "${WORK}/example.sh" <<SCRIPT
#!/bin/bash
source "${REPO}/Features/lib/st_feature_check.sh" "\$1"
echo EXAMPLE_RAN
SCRIPT

# expect NAME REQUIRED SERVER_BODY EXPECTED_EXIT RAN(yes|no) [OUTPUT_TEXT]
expect() {
    local name="$1" required="$2" body="$3" want_exit="$4" want_ran="$5" want_text="$6"
    printf '%s' "${body}" > "${WORK}/body.json"
    local out rc
    out=$(PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${WORK}/body.json" \
          bash "${WORK}/example.sh" "${required}" 2>/dev/null)
    rc=$?
    local ran=no
    [[ "${out}" == *EXAMPLE_RAN* ]] && ran=yes
    if [ "${rc}" -eq "${want_exit}" ] && [ "${ran}" = "${want_ran}" ] \
       && { [ -z "${want_text}" ] || [[ "${out}" == *"${want_text}"* ]]; }; then
        pass "${name}"
    else
        fail "${name}  (exit ${rc}, ran ${ran}; wanted exit ${want_exit}, ran ${want_ran})"
    fi
}

echo "=== Versions at or after the introducing version run the example ==="
expect "same version"                 "5.5-20260924" '{"version":"5.5-20260924"}' 0 yes "Version check passed"
expect "later day, same month"        "5.5-20260924" '{"version":"5.5-20260925"}' 0 yes
expect "later month"                  "5.5-20260924" '{"version":"5.5-20261015"}' 0 yes
expect "next year's update"           "5.5-20260924" '{"version":"5.5-20270105"}' 0 yes
expect "later minor release"          "5.5-20260924" '{"version":"5.6"}'          0 yes
expect "later major release"          "5.5-20260924" '{"version":"6.0"}'          0 yes
expect "spacing around the colon"     "5.5-20260924" '{ "version" : "5.5-20260924" }' 0 yes
expect "month-only server, later month" "5.5-20260924" '{"version":"5.5-202610"}' 0 yes
expect "month-only requirement, later day" "5.5-202609" '{"version":"5.5-20260924"}' 0 yes

echo
echo "=== Older versions skip the example ==="
expect "earlier day, same month"      "5.5-20260924" '{"version":"5.5-20260923"}' 0 no "SKIPPED"
expect "earlier month"                "5.5-20260924" '{"version":"5.5-20260831"}' 0 no "SKIPPED"
expect "month-only server, same month" "5.5-20260924" '{"version":"5.5-202609"}'  0 no "SKIPPED"
expect "base release, no update"      "5.5-20260924" '{"version":"5.5"}'          0 no "SKIPPED"
expect "earlier minor release"        "5.5-20260924" '{"version":"5.4-99991231"}' 0 no "SKIPPED"
expect "earlier major release"        "5.5-20260924" '{"version":"4.9"}'          0 no "SKIPPED"
expect "numbers compare as numbers"   "5.10"         '{"version":"5.9"}'          0 no "SKIPPED"
expect "a feature from the base release runs on a later update" "5.5" '{"version":"5.5-20260924"}' 0 yes

echo
echo "=== A version that cannot be read stops the example with an error ==="
expect "empty response"               "5.5-20260924" ''                          1 no "could not read"
expect "no version field"             "5.5-20260924" '{"serverType":"x"}'        1 no "could not read"
expect "version is not a version"     "5.5-20260924" '{"version":"unknown"}'     1 no "could not read"
expect "bad version in the script"    "banana"     '{"version":"5.5-20260924"}'  1 no "not a version"

echo
echo "=== The real examples use it ==="
MISSING=0
while IFS= read -r f; do
    grep -q 'st_feature_check' "${REPO}/$f" || { fail "no version check: $f"; MISSING=1; }
done < <(cd "${REPO}" && git ls-files 'Features/*.sh' 'Features/*.bat' \
         | grep -v '^Features/lib/' | grep -vE '/(settings|post_admin|enduser)[^/]*$')
[ "${MISSING}" -eq 0 ] && pass "every feature example calls the version check"


# ------------------------------------------------------------------------------
# The other shared helpers in Features/lib: post_admin.sh, admin_calls.sh, enduser.sh and
# home_folder.sh, run directly against the stub curl, without a feature around them. The
# features' own tests (test_feature_*.sh) run every example through them; this pins what each
# helper returns and sends on its own: the code a call leaves behind, how a path is encoded,
# what a probe of a home folder makes of each answer, and how a run moves on to the next
# account name.
# ------------------------------------------------------------------------------
echo
echo "##### Features/lib: the shared helpers #####"
echo
LIBWORK="${WORK}/lib"
mkdir -p "${LIBWORK}"
export PATH="${WORK}/bin:${PATH}"
export FEATURE_DIR="${LIBWORK}"
source "${TESTS_DIR}/fixtures/set_variables.test.sh"
export ST_PORT="444"
export EU_ACCOUNT="someone" EU_ACCOUNT_PASSWORD="pw" EU_ENDUSER_PORT="8443"
export STUB_CURL_CSRF="csrf-abc"
source "${REPO}/Features/lib/post_admin.sh"
source "${REPO}/Features/lib/admin_calls.sh"
source "${REPO}/Features/lib/enduser.sh"
source "${REPO}/Features/lib/home_folder.sh"

# what the stub saw on stderr, per call: METHOD URL
LOG="${LIBWORK}/log.txt"
calls() { awk '/^METHOD:/ {m=$2} /^URL:/ {print m, $2}' "${LOG}"; }
call_count() { calls | grep -c "$1"; }

echo "=== ar_encode_path ==="
[ "$(ar_encode_path 'files/a b/c#d')" = "files/a%20b/c%23d" ] && pass "a space and a # are encoded, the / between the segments stays" || fail "space and #: $(ar_encode_path 'files/a b/c#d')"
[ "$(ar_encode_path 'files/50% off?.txt')" = "files/50%25%20off%3F.txt" ] && pass "a % and a ? are encoded too" || fail "% and ?: $(ar_encode_path 'files/50% off?.txt')"
[ "$(ar_encode_path 'files//x')" = "files//x" ] && pass "an empty segment stays empty" || fail "empty segment: $(ar_encode_path 'files//x')"
[ "$(ar_encode_path 'files/é.txt')" = "files/%C3%A9.txt" ] && pass "a character outside ASCII is encoded as UTF-8" || fail "utf-8: $(ar_encode_path 'files/é.txt')"
[ "$(ar_encode_path 'accounts/arTest_Account-1.x~y')" = "accounts/arTest_Account-1.x~y" ] && pass "letters, digits and - _ . ~ are left alone" || fail "plain name changed"
[ "$(ar_encode_path 'myself')" = "myself" ] && pass "a path with one segment is unchanged" || fail "myself"

echo
echo "=== ar_admin_exists ==="
for pair in "200:0" "404:1" "401:2" "500:2" "201:2"; do
    status="${pair%%:*}" want="${pair##*:}"
    STUB_CURL_STATUS_HEAD="${status}" ar_admin_exists "accounts/x" 2>"${LOG}"
    rc=$?
    [ "${rc}" -eq "${want}" ] && [ "${AR_ADMIN_CODE}" = "${status}" ] && pass "HEAD answers ${status}: returns ${want}, and AR_ADMIN_CODE is ${status}" || fail "HEAD ${status}: returned ${rc}, code ${AR_ADMIN_CODE}"
done
curl() { return 7; }
ar_admin_exists "accounts/x"; rc=$?
[ "${rc}" -eq 2 ] && [ "${AR_ADMIN_CODE}" = "000" ] && pass "no answer at all: returns 2 (nobody knows), code 000" || fail "no answer: ${rc} ${AR_ADMIN_CODE}"
unset -f curl
STUB_CURL_STATUS_HEAD=200 ar_admin_exists "accounts/my account" 2>"${LOG}"
calls | grep -q '^HEAD https://st.example.com:444/api/v2.0/accounts/my%20account$' && pass "the path goes into the URL encoded" || fail "url: $(calls)"

echo
echo "=== ar_admin_delete ==="
OUT=$(STUB_CURL_STATUS=204 ar_admin_delete "routes/abc" 2>"${LOG}"); rc=$?
[ "${rc}" -eq 0 ] && [[ "${OUT}" == *"HTTP 204"* ]] && pass "a 204: returns 0, and prints the code" || fail "204: ${rc} ${OUT}"
OUT=$(STUB_CURL_STATUS=403 ar_admin_delete "routes/abc" 2>"${LOG}"); rc=$?
[ "${rc}" -eq 1 ] && [[ "${OUT}" == *"HTTP 403"* ]] && pass "a 403: returns 1, and prints the code" || fail "403: ${rc} ${OUT}"
STUB_CURL_STATUS=404 ar_admin_delete "routes/abc" >/dev/null 2>&1; rc=$?
[ "${rc}" -eq 1 ] && [ "${AR_ADMIN_CODE}" = "404" ] && pass "a 404: returns 1, and AR_ADMIN_CODE says 404 (so a caller can tell 'already gone')" || fail "404: ${rc} ${AR_ADMIN_CODE}"
STUB_CURL_STATUS=204 ar_admin_delete "applications/my app#1" >/dev/null 2>"${LOG}"
calls | grep -q '^DELETE https://st.example.com:444/api/v2.0/applications/my%20app%231$' && pass "a name with a space and a # is encoded in the URL" || fail "url: $(calls)"
curl() { return 7; }
OUT=$(ar_admin_delete "routes/abc"); rc=$?
[ "${rc}" -eq 1 ] && [[ "${OUT}" == *"HTTP 000"* ]] && pass "no answer at all: returns 1 and prints HTTP 000" || fail "no answer: ${rc} ${OUT}"
OUT=$(ar_admin_post "routes" '{}'); rc=$?
[ "${rc}" -eq 1 ] && [[ "${OUT}" == *"HTTP 000"* ]] && pass "ar_admin_post with no answer at all: returns 1 and prints HTTP 000, not an empty code" || fail "post no answer: ${rc} ${OUT}"
unset -f curl

echo
echo "=== ar_admin_post ==="
rm -f "${FEATURE_DIR}/state.local.sh"
OUT=$(STUB_CURL_STATUS=409 ar_admin_post "sites" '{}' KEY 2>"${LOG}"); rc=$?
[ "${rc}" -eq 1 ] && [[ "${OUT}" == *"HTTP 409"* ]] && [ ! -f "${FEATURE_DIR}/state.local.sh" ] && pass "a 409: returns 1, prints the code, saves nothing" || fail "409: ${rc}"
STUB_CURL_STATUS=201 STUB_CURL_LOCATION_ID=id-9 ar_admin_post "sites" '{}' KEY >/dev/null 2>"${LOG}"; rc=$?
[ "${rc}" -eq 0 ] && [ "${AR_ADMIN_CODE}" = "201" ] && grep -q 'KEY=id-9' "${FEATURE_DIR}/state.local.sh" && pass "a 201: returns 0, AR_ADMIN_CODE is 201, and the id from the Location header is saved" || fail "201: ${rc} ${AR_ADMIN_CODE}"
rm -f "${FEATURE_DIR}/state.local.sh"

echo
echo "=== ar_enduser_call ==="
AR_EU_JAR="${LIBWORK}/jar.txt"; AR_EU_CSRF="csrf-abc"
STUB_CURL_STATUS=200 ar_enduser_call GET "files/subscription/my file#1.txt" "" >/dev/null 2>"${LOG}"
calls | grep -q '^GET https://st.example.com:8443/api/v2.0/files/subscription/my%20file%231.txt$' && pass "each segment of the path is encoded; a # no longer cuts the path short" || fail "url: $(calls)"
STUB_CURL_STATUS=200 ar_enduser_call GET "files/a/b" "" >/dev/null 2>"${LOG}"
calls | grep -q '^GET https://st.example.com:8443/api/v2.0/files/a/b$' && pass "a plain path is unchanged" || fail "url: $(calls)"
STUB_CURL_STATUS=204 ar_enduser_call DELETE "files/x#y" "" >/dev/null 2>"${LOG}"
calls | grep -q '^DELETE .*/files/x%23y$' && pass "DELETE is encoded the same way" || fail "url: $(calls)"
STUB_CURL_STATUS=403 ar_enduser_call GET "files/x" "" >/dev/null 2>&1; rc=$?
[ "${rc}" -eq 1 ] && [ "${AR_EU_CODE}" = "403" ] && pass "a 403: returns 1, AR_EU_CODE says 403" || fail "403: ${rc} ${AR_EU_CODE}"
curl() { return 7; }
ar_enduser_call GET "files/x" "" >/dev/null 2>&1; rc=$?
[ "${rc}" -eq 1 ] && [ "${AR_EU_CODE}" = "000" ] && pass "no answer at all: returns 1, AR_EU_CODE is 000, not empty" || fail "no answer: ${rc} '${AR_EU_CODE}'"
unset -f curl

echo
echo "=== ar_home_probe ==="
SEQ="${LIBWORK}/seq.txt"
STALE="${LIBWORK}/stale.json"; echo '{"validationErrors":["Error occurred while creating file: null"]}' > "${STALE}"
OTHER="${LIBWORK}/other.json"; echo '{"validationErrors":["something else"]}' > "${OTHER}"
probe() { # probe SEQUENCE_TEXT -> rc, with the stub's calls in LOG
    printf "$1" > "${SEQ}"; rm -f "${SEQ}.served"
    STUB_CURL_FILES_POST_SEQUENCE="${SEQ}" ar_home_probe "somebody" "my_probe" >/dev/null 2>"${LOG}"
}
probe '201\n'; rc=$?
[ "${rc}" -eq 0 ] && [ "$(call_count '^POST .*/files/my_probe$')" -eq 1 ] && [ "$(call_count '^DELETE .*/files/my_probe$')" -eq 1 ] && pass "a usable home: returns 0, and the probe folder is made and removed" || fail "usable: ${rc} $(calls | grep probe)"
probe '403\t'"${STALE}"'\n'; rc=$?
[ "${rc}" -eq 1 ] && [ "$(call_count '^DELETE .*/files/my_probe$')" -eq 0 ] && pass "a 403 'Error occurred while creating file': returns 1 (stale), nothing to remove" || fail "stale: ${rc}"
probe '403\t'"${OTHER}"'\n'; rc=$?
[ "${rc}" -eq 2 ] && pass "a 403 for another reason: returns 2 (could not tell)" || fail "other 403: ${rc}"
probe '409\t'"${OTHER}"'\n'; rc=$?
[ "${rc}" -eq 2 ] && pass "a 409 (the probe folder is there): returns 2 (could not tell)" || fail "409: ${rc}"
printf '201\n' > "${SEQ}"; rm -f "${SEQ}.served"
STUB_CURL_STATUS=401 STUB_CURL_FILES_POST_SEQUENCE="${SEQ}" ar_home_probe "somebody" "my_probe" >/dev/null 2>"${LOG}"; rc=$?
[ "${rc}" -eq 2 ] && [ "$(call_count '/files/')" -eq 0 ] && pass "a login that fails: returns 2, and no folder is made" || fail "login failed: ${rc}"
printf '201\n' > "${SEQ}"; rm -f "${SEQ}.served"
OUT=$(STUB_CURL_STATUS_DELETE=403 STUB_CURL_FILES_POST_SEQUENCE="${SEQ}" ar_home_probe "somebody" "my_probe" 2>"${LOG}"); rc=$?
[ "${rc}" -eq 0 ] && [[ "${OUT}" == *"The probe folder my_probe could not be removed from the home of somebody (HTTP 403)."* ]] && pass "a probe folder that cannot be removed: still 0, and it says so" || fail "probe delete refused: ${rc} ${OUT}"
STUB_CURL_FILES_POST_SEQUENCE="${SEQ}" ar_home_probe "somebody" "my_probe" >/dev/null 2>"${LOG}"
grep -q '^BASIC_AUTH: somebody:pw$' "${LOG}" && pass "it logs in as the account it was given" || fail "login: $(grep BASIC_AUTH "${LOG}")"

echo
echo "=== ar_ensure_usable_home ==="
# The caller's ar_switch_account: remember the name, and say whether it worked
SWITCHED=""
SWITCH_RC=0
ar_switch_account() { SWITCHED="${SWITCHED}$1 "; return "${SWITCH_RC}"; }
ensure() { # ensure SEQUENCE_TEXT [VAR=value...]: DEFAULT is "base", the run starts as "base"
    printf "$1" > "${SEQ}"; rm -f "${SEQ}.served"
    shift
    SWITCHED=""
    OUT=$(env "$@" STUB_CURL_FILES_POST_SEQUENCE="${SEQ}" bash -c '
        source "$0/Features/lib/post_admin.sh"; source "$0/Features/lib/admin_calls.sh"
        source "$0/Features/lib/enduser.sh"; source "$0/Features/lib/home_folder.sh"
        ar_switch_account() { printf "SWITCHED %s\n" "$1"; return "${SWITCH_RC:-0}"; }
        ar_ensure_usable_home base base probe_dir; rc=$?
        printf "RETURNED %s ACCOUNT %s\n" "${rc}" "${AR_HOME_ACCOUNT}"' "${REPO}" 2>"${LOG}")
}
HEAD_NONE=404   # an existence check that answers 404: every name is free
ensure '201\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE}
[[ "${OUT}" == *"RETURNED 0 ACCOUNT base"* ]] && [[ "${OUT}" != *"SWITCHED"* ]] && [ "$(call_count '^DELETE .*/accounts/')" -eq 0 ] && pass "a usable home: returns 0, the account is kept, nothing is switched or deleted" || fail "usable: ${OUT}"
ensure '403\t'"${STALE}"'\n201\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE}
if [[ "${OUT}" == *"SWITCHED base_2"* ]] && [[ "${OUT}" == *"RETURNED 0 ACCOUNT base_2"* ]] && [[ "${OUT}" == *"A new name is used: base_2."* ]] \
   && [ "$(calls | grep '^DELETE .*/accounts/' | sed 's#.*/accounts/##' | tr '\n' ' ')" = "base " ]; then
    pass "a stale home: the old account is deleted, the run is switched to base_2, and says why"
else
    fail "stale: ${OUT}"
fi
ensure '403\t'"${STALE}"'\n201\n' STUB_CURL_STATUS_HEAD=200
[[ "${OUT}" == *"RETURNED 1 ACCOUNT base"* ]] && [[ "${OUT}" == *"every name up to base_9"* ]] && [[ "${OUT}" == *"Run ./99.cleanup_DELETE.sh base to remove what this created."* ]] && [ "$(call_count '^DELETE .*/accounts/')" -eq 0 ] \
    && pass "every name taken: returns 1 with a message, and deletes nothing" || fail "all taken: ${OUT}"
ensure '403\t'"${STALE}"'\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE}
[[ "${OUT}" == *"RETURNED 1 ACCOUNT base_9"* ]] && [[ "${OUT}" == *"every name up to base_9"* ]] \
    && [ "$(calls | grep '^DELETE .*/accounts/' | sed 's#.*/accounts/##' | tr '\n' ' ')" = "base base_2 base_3 base_4 base_5 base_6 base_7 base_8 " ] \
    && pass "every name stale: moves through base_2 to base_9, deletes only the ones it made, then returns 1" || fail "all stale: $(echo "${OUT}" | tail -n 3)"
ensure '403\t'"${STALE}"'\n201\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE} STUB_CURL_STATUS_DELETE=403
[[ "${OUT}" == *"The account base could not be deleted, so the run stops here."* ]] && [[ "${OUT}" == *"RETURNED 1 ACCOUNT base"* ]] && [[ "${OUT}" != *"SWITCHED"* ]] \
    && pass "an account that cannot be deleted: returns 1 before it switches anything" || fail "delete refused: ${OUT}"
ensure '403\t'"${STALE}"'\n201\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE} SWITCH_RC=1
[[ "${OUT}" == *"SWITCHED base_2"* ]] && [[ "${OUT}" == *"RETURNED 1 "* ]] \
    && pass "a switch that fails (the caller could not create the new account): returns 1" || fail "switch failed: ${OUT}"
ensure '409\t'"${OTHER}"'\n' STUB_CURL_STATUS_HEAD=${HEAD_NONE}
[[ "${OUT}" == *"RETURNED 0 ACCOUNT base"* ]] && [[ "${OUT}" != *"SWITCHED"* ]] && pass "an answer it cannot read: returns 0, the example that makes the folders reports it" || fail "unreadable: ${OUT}"

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_feature_version_check: PASS"; else echo "test_feature_version_check: FAIL"; fi
exit "${FAILED}"
