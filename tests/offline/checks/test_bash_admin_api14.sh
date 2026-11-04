#!/bin/bash
# ==============================================================================
# Run the Admin API 1.4 examples (Admin/API 1.4/bash) against a stub curl, and check the call each one makes: the method, the
# URL (the /api/v1.4 base), the form fields (the API 1.4 takes form data, not JSON), the credentials, the headers, what it
# prints for an answer, and its exit code.
#
# 01 validPath: 200 is a valid path (a path with spaces and a quote goes as one field), 403 with the reason, 400 for an empty
# path from the server, 415; 02 path: the four questions by default, a chosen few, the answer printed line by line, a refusal;
# both: wrong use is exit 2 with nothing sent, a missing settings file is exit 1 with nothing sent.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
API14="${REPO}/Admin/API 1.4/bash"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_api14"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 1.4"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp -R "${API14}" "${WORK}/tree/API 1.4/"
TREE="${WORK}/tree/API 1.4/bash"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${TREE}/set_variables.local.sh"
BASE="https://st.example.com:8444/api/v1.4"

# run SCRIPT [PARAMS]: STATUS is the status the stub prints, BODY the file it serves for a POST
run() {
    local rel="$1"; shift
    OUT=$(cd "${TREE}/01.Validation" && env -u ST_ADMIN_LOCAL_VARIABLES PATH="${WORK}/bin:${PATH}" STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_PRINT_CODE=1 STUB_CURL_POST_BODY="${BODY:-}" \
          bash "./${rel}" "$@" 2>&1)
    RC=$?
}
body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
ncalls() { printf '%s\n' "${OUT}" | grep -c '^METHOD:'; }
url() { printf '%s\n' "${OUT}" | sed -n 's/^URL: //p' | head -1; }
fields() { printf '%s\n' "${OUT}" | sed -n 's/^FORM_FIELD: //p' | tr '\n' ' '; }

echo "=== 01.validation_validPath_POST ==="
run 01.validation_validPath_POST.sh /data/inbox
expect "01: a valid path is exit 0, one POST to the 1.4 validPath" "${RC}:$(ncalls):$(printf '%s\n' "${OUT}" | grep -c '^METHOD: POST')" "0:1:1"
expect "01: the URL is /api/v1.4/validation/validPath" "$(url)" "${BASE}/validation/validPath"
expect "01: the path is a form field, not JSON" "$(fields)" "path=/data/inbox "
hasnt "01: and no JSON body is sent" "PAYLOAD_B64"
has "01: as the administrator (Basic authentication)" "BASIC_AUTH: apiadmin:"
has "01: with a Referer" "HEADER: Referer:"
has "01: it says the path is valid" "/data/inbox is a valid path (HTTP 200)."
run 01.validation_validPath_POST.sh "/data/my inbox/it's"
expect "01: a path with a space and a quote goes as one field" "$(fields)" "path=/data/my inbox/it's "
STATUS=403 BODY="$(body e1 '{"validationErrors":["Path cannot be in the unsafe paths list."],"message":"Error validating request"}')" run 01.validation_validPath_POST.sh /etc
expect "01: a refused path is exit 1" "${RC}" "1"
has "01: with the reason the server gives" "/etc is refused (HTTP 403): Path cannot be in the unsafe paths list."
STATUS=400 BODY="$(body e2 '{"validationErrors":["validatePath.arg0 may not be empty"]}')" run 01.validation_validPath_POST.sh "x"
has "01: a 400 shows its reason" "refused (HTTP 400): validatePath.arg0 may not be empty"
STATUS=415 BODY="$(body e3 '{"message":null}')" run 01.validation_validPath_POST.sh /x
expect "01: a 415 (an answer with no reason) is exit 1 and prints the answer" "${RC}" "1"
STATUS=403 BODY="$(body e4 'Forbidden, plain text')" run 01.validation_validPath_POST.sh /x
has "01: an answer that is not JSON is printed as it is" "Forbidden, plain text"
run 01.validation_validPath_POST.sh
expect "01: no path is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: with the usage" "Usage: ./01.validation_validPath_POST.sh PATH"
run 01.validation_validPath_POST.sh ""
expect "01: an empty path is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 01.validation_validPath_POST.sh /a /b
expect "01: two paths are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm "${TREE}/set_variables.local.sh"
run 01.validation_validPath_POST.sh /a
expect "01: no settings file is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
has "01: and it says to copy the example file" "Copy set_variables.local.example.sh to set_variables.local.sh"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${TREE}/set_variables.local.sh"

echo "=== 02.validation_path_POST ==="
ANSWER='{"isFile":"true","relativePath":"/etc/hostname","isValid":"true","absolutePath":"/etc/hostname","isExist":"true","isDirectory":"false"}'
BODY="$(body a1 "${ANSWER}")" run 02.validation_path_POST.sh /etc/hostname
expect "02: exit 0, one POST to the 1.4 path operation" "${RC}:$(ncalls):$(url)" "0:1:${BASE}/validation/path"
expect "02: by default it asks all four questions, with the path as inputPath" "$(fields)" "inputPath=/etc/hostname validate=true exist=true isDirectory=true isFile=true "
has "02: it prints the answer, a line for each field" "  isExist: true"
has "02: ... all of them" "  absolutePath: /etc/hostname"
has "02: ... and the path with the status" "/etc/hostname (HTTP 200)"
BODY="$(body a2 '{"relativePath":"/no/such","isValid":"true","absolutePath":"/no/such","isExist":"false"}')" run 02.validation_path_POST.sh /no/such exist,isDirectory
expect "02: a chosen few go, in the order given" "$(fields)" "inputPath=/no/such exist=true isDirectory=true "
has "02: a path that is not there says so" "  isExist: false"
run 02.validation_path_POST.sh /tmp validate
expect "02: one question" "$(fields)" "inputPath=/tmp validate=true "
run 02.validation_path_POST.sh /tmp bogus
expect "02: a question the server does not know is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: and it names the word" "ASK has 'bogus'"
run 02.validation_path_POST.sh /tmp "exist,,isFile"
expect "02: an empty word in the list is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
STATUS=400 BODY="$(body e5 '{"validationErrors":["pathOperations.arg0 may not be empty"]}')" run 02.validation_path_POST.sh /tmp
expect "02: a refusal is exit 1" "${RC}" "1"
has "02: with its reason" "The server refused the question (HTTP 400): pathOperations.arg0 may not be empty"
run 02.validation_path_POST.sh
expect "02: no path is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "02: with the usage" "Usage: ./02.validation_path_POST.sh PATH [ASK]"
run 02.validation_path_POST.sh /a b c
expect "02: three parameters are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
rm "${TREE}/set_variables.local.sh"
run 02.validation_path_POST.sh /a
expect "02: no settings file is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${TREE}/set_variables.local.sh"

echo "=== the folder ==="
for f in "01.Validation/01.validation_validPath_POST.sh" "01.Validation/02.validation_path_POST.sh"; do
    [ -x "${API14}/${f}" ] && pass "${f} is there and executable" || fail "${f} is missing or not executable"
done
grep -q "^# Risk: read" "${API14}/01.Validation/01.validation_validPath_POST.sh" && grep -q "^# Risk: read" "${API14}/01.Validation/02.validation_path_POST.sh" && pass "both say Risk: read (they change nothing)" || fail "a Risk line is wrong"
[ -f "${API14}/set_variables.local.example.sh" ] && pass "the example settings file is there" || fail "no set_variables.local.example.sh"
README="${REPO}/Admin/API 1.4/README.md"
for word in "validation/validPath" "validation/path" "transfers/resubmit" "09-resubmit-transfers" "addressBookSettings" "unlicensed" "generateReport" "routeTemplate" "objectTypes" "415"; do
    grep -qF -- "${word}" "${README}" && pass "README says: ${word}" || fail "README does not say: ${word}"
done

echo
if [ "${FAILED}" -eq 0 ]; then echo "test_bash_admin_api14: PASS"; else echo "test_bash_admin_api14: FAIL"; fi
exit "${FAILED}"
