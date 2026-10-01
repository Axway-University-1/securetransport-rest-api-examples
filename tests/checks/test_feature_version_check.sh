#!/bin/bash
# ==============================================================================
# Check Features/lib/st_feature_check.sh against a stub curl.
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

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_feature_version_check: PASS"; else echo "test_feature_version_check: FAIL"; fi
exit "${FAILED}"
