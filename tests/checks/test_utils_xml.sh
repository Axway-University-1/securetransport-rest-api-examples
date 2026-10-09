#!/bin/bash
# ==============================================================================
# Run the two XML tools in python/utils against synthetic fixtures.
#
# Neither tool needs a server for the part exercised here, so this is a real end
# to end run of the shipped code, not a stub.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
UTILS="$(cd ../Admin/API\ 2.0/python/utils && pwd)"
FIX="${TESTS_DIR}/fixtures"
OUT="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/utils"

rm -rf "${OUT}" && mkdir -p "${OUT}"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }

echo "=== stCompareExportedConfigurations.py ==="

python3 "${UTILS}/stCompareExportedConfigurations.py" \
        "${FIX}/config_a.xml" "${FIX}/config_b.xml" > "${OUT}/compare_ab.txt" 2>&1

grep -q "Options whose value differs: 1"      "${OUT}/compare_ab.txt" && pass "finds the differing value" || fail "differing value not reported"
grep -q "Options only in .*config_a.xml: 1"   "${OUT}/compare_ab.txt" && pass "finds what is only in the first file" || fail "only-in-first not reported"
grep -q "Options only in .*config_b.xml: 2"   "${OUT}/compare_ab.txt" && pass "finds what is only in the second file" || fail "only-in-second not reported"
grep -q "AddressBook.Enabled"                 "${OUT}/compare_ab.txt" && pass "names the option that differs" || fail "differing option not named"

# An option with no value must not be reported as a difference
if grep -q "NoValueHere" "${OUT}/compare_ab.txt"; then
    fail "an option with no value in either file was reported as different"
else
    pass "an option with no value in both files is not a difference"
fi

# File 1 is the smaller one here. The python2 version refused this case.
python3 "${UTILS}/stCompareExportedConfigurations.py" \
        "${FIX}/config_b.xml" "${FIX}/config_a.xml" > "${OUT}/compare_ba.txt" 2>&1
if grep -q "reversing the order" "${OUT}/compare_ba.txt"; then
    fail "still asks for the arguments to be reversed"
else
    pass "compares in both directions regardless of argument order"
fi
grep -q "Options only in .*config_a.xml: 1" "${OUT}/compare_ba.txt" && pass "reversed run is the mirror image" || fail "reversed run is not the mirror image"

echo
echo "=== processSystemConfig.py ==="

# It writes next to itself, so keep the workspace clean afterwards
rm -f "${UTILS}/convertedUserClasses.xml" "${UTILS}/extractUserClasses.log"
python3 "${UTILS}/processSystemConfig.py" "${FIX}/userclasses.xml" > "${OUT}/userclasses.txt" 2>&1

grep -q "Total Number of UserClasses: 3" "${OUT}/userclasses.txt" && pass "reads every user class" || fail "wrong user class count"
grep -q "converted to the 5.5 form: 1"   "${OUT}/userclasses.txt" && pass "converts only the memberof expression" || fail "wrong conversion count"
grep -q "createOnTarget is False"        "${OUT}/userclasses.txt" && pass "sends nothing to a server by default" || fail "did not report the safe default"

CONV="${UTILS}/convertedUserClasses.xml"
if [ -f "${CONV}" ]; then
    pass "writes the converted XML"
    grep -q 'isset("LDAP_DIR_memberOf") ? memberof' "${CONV}" && pass "memberof wrapped in the 5.5 form" || fail "memberof not converted"
    grep -q '<expression>user == "bob"</expression>' "${CONV}" && pass "a plain expression is left alone" || fail "plain expression was altered"
    # The class with no expression must still be written, without an empty element
    if grep -q "<name>NoExpressionAtAll</name>" "${CONV}"; then
        pass "a class with no expression is still written"
    else
        fail "a class with no expression was dropped"
    fi
    if grep -q "<expression>None</expression>" "${CONV}"; then
        fail "a missing expression was written as the string None"
    else
        pass "a missing expression is omitted, not written as None"
    fi

    # A second run must replace, not append. The python2 version appended.
    BEFORE=$(grep -c "<UserClass>" "${CONV}")
    python3 "${UTILS}/processSystemConfig.py" "${FIX}/userclasses.xml" >/dev/null 2>&1
    AFTER=$(grep -c "<UserClass>" "${CONV}")
    if [ "${BEFORE}" -eq "${AFTER}" ]; then
        pass "a second run replaces the output rather than appending"
    else
        fail "output grew from ${BEFORE} to ${AFTER} blocks on a second run"
    fi
else
    fail "no converted XML was written"
fi

mv -f "${CONV}" "${OUT}/" 2>/dev/null
rm -f "${UTILS}/extractUserClasses.log"

echo
if [ "${FAILED}" -eq 0 ]; then
    echo "test_utils_xml: PASS"
else
    echo "test_utils_xml: FAIL"
fi
exit "${FAILED}"
