#!/bin/bash
# ==============================================================================
# Run EndUser/UseCases/08-lists-and-paging against a stub curl, and check the calls each script makes: the method,
# the URL and the query it builds (limit, offset, sortBy, order, fields), the body of a POST, what it prints about the
# answers, and its exit code.
#
# 01 the folder and the files made, the Location of each (a new folder has none) checked against the file name; 02 the
# folder list (an object with no count, the walk that ends on a short page, limit=0 that returns nothing, the sort,
# the two limits the server cannot use); 03 /transfers (a plain array, the default page of 100, exit 3 when the account
# may not use it); 04 the address book and the secret questions; 05 fields= that has no effect, and an answer that is
# narrower with it; 06 counting by reading pages; 99 the exact names, twice; 00 failing fast, an exit 3 that is a skip,
# and a whole run.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/EndUser/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_enduser_usecase_08"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

# the stub, behind the wrapper that answers each method with its own status, and behind a second wrapper that gives the
# Nth upload (a POST with -F) a Location that ends in lst_0N.txt (LOC_OVERRIDE names another ending, for one test)
cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl_by_method" && chmod +x "${WORK}/bin/curl_by_method"
cat > "${WORK}/bin/curl" <<'WRAP'
#!/bin/bash
case " $* " in
    *" -F "*)
        n=$(( $(cat "${STUB_COUNTER}.up" 2>/dev/null || echo 0) + 1 )); echo "${n}" > "${STUB_COUNTER}.up"
        export STUB_CURL_LOCATION_ID="${LOC_OVERRIDE:-$(printf 'lst_%02d.txt' "${n}")}" ;;
esac
exec "$(dirname "$0")/curl_by_method" "$@"
WRAP
chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/08-lists-and-paging" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
UC="${WORK}/tree/UseCases/08-lists-and-paging"
F="${BASE}/files/example_uc_lists"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
RULE_N=0
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# files_json FIRST COUNT: the answer of a folder list: COUNT entries named lst_NN.txt from number FIRST, and self
files_json() {
    jq -cn --argjson first "$1" --argjson count "$2" \
      '{files: [range($first; $first + $count) | {fileName: ("lst_" + (if . < 10 then "0" else "" end) + (. | tostring) + ".txt"), isDirectory: false, size: 45}], self: {fileName: "example_uc_lists", isDirectory: true}}'
}
# array_json COUNT: a plain array of COUNT transfers, newest first
array_json() { jq -cn --argjson n "$1" '[range(0; $n) | {filename: ("t" + (. | tostring) + ".txt"), startTime: ("Fri, 30 Oct 2026 08:00:" + (if (59 - .) < 10 then "0" else "" end) + ((59 - .) | tostring) + " +0200"), direction: "Incoming", protocol: "http", status: "Success"}]'; }
reset_counters() { rm -f "${WORK}"/ctr.*; }

run() {
    local rel="$1"; shift
    touch "${UC}/session.cookie.jar"
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-}" STUB_CURL_GET_RULES="${RULES:-}" STUB_COUNTER="${WORK}/ctr" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_CURL_STATUS_GET="${STATUS_GET:-}" STUB_CURL_PRINT_CODE=1 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }      # without the check of the session that comes first (GET /myself)
ncalls() { calls | wc -l | tr -d ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }

SEVEN="$(body seven "$(files_json 1 7)")"
ERR_404="$(body err404 '{"message":"HTTP 404 Not Found"}')"
ERR_NEG="$(body errneg '{"message":"Parameter should be a positive number or 0."}')"
NOT_ALLOWED="$(body notallowed '{"message":"User: john is not authorized to get/submit transfers via ST RESTful API."}')"

echo "=== 01 the folder, the files, the Location header ==="
reset_counters
STUB_STATUS_GET_SEQ="200 404 200" STUB_STATUS_POST=201 GET_BODY="${SEVEN}" run 01.files_POST_location.sh
expected="GET ${F}?metadata=true POST ${F}"; for n in 1 2 3 4 5 6 7; do expected="${expected} POST ${F}"; done
expect "01: looks for the folder, makes it, uploads 7 files, reads the first back by its Location" "${RC}:$(ucalls | tr '\n' ' ')" "0:${expected} GET ${F}/lst_01.txt "
expect "01: the folder is made with a body that says it is a directory" "$(payload 1 | jq -c '[.isDirectory, .isRegularFile]')" '[true,false]'
has "01: says what happened to the folder" "Create the folder 'example_uc_lists': HTTP 201"
has "01: a new folder has no Location" "Location: none. A new folder has no Location header."
has "01: the Location of a file is shown" "Location: ${F}/lst_03.txt"
has "01: the file name is in the upload" "filename=lst_07.txt"
has "01: and the last upload is the seventh" "Upload example_uc_lists/lst_07.txt: HTTP 201"
hasnt "01: and there is no eighth" "lst_08.txt"
has "01: the first Location is read back" "GET of the first Location: HTTP 200"
reset_counters
STUB_STATUS_POST=201 GET_BODY="${SEVEN}" run 01.files_POST_location.sh 2
expect "01: a folder that is there is used as it is: no POST for it, and COUNT is how many files" "$(ucalls | grep -c '^POST')" "2"
has "01: and it says so" "The folder 'example_uc_lists' is there already: it is used as it is."
reset_counters
STUB_STATUS_GET_SEQ="200 404" STUB_STATUS_POST=500 run 01.files_POST_location.sh
expect "01: a folder that cannot be made is exit 1, after the one POST" "${RC}:$(ucalls | grep -c '^POST')" "1:1"
reset_counters
STUB_STATUS_POST_SEQ="201 500" run 01.files_POST_location.sh
expect "01: an upload that is refused is exit 1, with no more uploads" "${RC}:$(ucalls | grep -c '^POST')" "1:2"
has "01: with its code" "Upload example_uc_lists/lst_02.txt: HTTP 500"
reset_counters
LOC_OVERRIDE=other.txt STUB_STATUS_POST=201 run 01.files_POST_location.sh 1
expect "01: a Location that does not end with the file name is exit 1" "${RC}" "1"
has "01: with the reason" "The Location does not end with the name of the file (lst_01.txt)."
reset_counters
STUB_STATUS_GET_SEQ="200 200 404" STUB_STATUS_POST=201 run 01.files_POST_location.sh 1
expect "01: a first Location that cannot be read is exit 1" "${RC}" "1"
for bad in 0 21 x; do
    run 01.files_POST_location.sh "${bad}"
    expect "01: a COUNT of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "01: with the range and the usage" "COUNT is 'x': it must be a whole number from 1 to 20."
run 01.files_POST_location.sh 2 3
expect "01: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 02 the list of a folder ==="
P1="$(body p1 "$(files_json 1 3)")"; P2="$(body p2 "$(files_json 4 3)")"; P3="$(body p3 "$(files_json 7 1)")"
EMPTY="$(body empty '{"files":[],"self":{"fileName":"example_uc_lists"}}')"
DESC="$(body desc "$(files_json 1 7 | jq -c '.files |= reverse')")"
list_rules() { rules 'limit=abc' "${ERR_404}" 'limit=-1' "${SEVEN}" 'order=DESC' "${DESC}" 'order=ASC' "${SEVEN}" 'limit=0' "${EMPTY}" 'limit=3&offset=0' "${P1}" 'limit=3&offset=3' "${P2}" 'limit=3&offset=6' "${P3}"; }
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 200 200 200 404 200" GET_BODY="${SEVEN}" RULES="$(list_rules)" run 02.files_GET_list.sh
expect "02: the folder whole, three pages, limit=0, the two sorts, then the two limits it cannot use" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${F} GET ${F}?limit=3&offset=0 GET ${F}?limit=3&offset=3 GET ${F}?limit=3&offset=6 GET ${F}?limit=0 GET ${F}?sortBy=fileName&order=DESC GET ${F}?sortBy=fileName&order=ASC GET ${F}?limit=abc GET ${F}?limit=-1 "
has "02: says the answer has no count, and names its keys" "The answer is an object with files, self: no count. With no limit it holds all 7 entries."
has "02: shows the pages" "page 2: offset 3, 3 entries"
has "02: and the short last page" "page 3: offset 6, 1 entries"
has "02: adds them up and says how the end is known" "Read 7 entries in 3 pages, the last one shorter than 3: that is the only sign of the end."
has "02: limit=0 returns nothing" "limit=0: HTTP 200, 0 entries. Not the default page and not all: none."
has "02: DESC starts at the last name" "sortBy=fileName&order=DESC: HTTP 200, first lst_07.txt, last lst_01.txt"
has "02: ASC at the first" "sortBy=fileName&order=ASC: HTTP 200, first lst_01.txt, last lst_07.txt"
has "02: limit=abc is shown with the answer it gets" "limit=abc: HTTP 404, HTTP 404 Not Found"
has "02: limit=-1 is shown too" "limit=-1: HTTP 200, 7 entries"
SIX="$(body six "$(files_json 1 6)")"; Q1="$(body q1 "$(files_json 1 3)")"; Q2="$(body q2 "$(files_json 4 3)")"
reset_counters
GET_BODY="${SIX}" RULES="$(rules 'limit=0' "${EMPTY}" 'limit=3&offset=0' "${Q1}" 'limit=3&offset=3' "${Q2}" 'limit=3&offset=6' "${EMPTY}")" run 02.files_GET_list.sh
has "02: a folder that is a multiple of the limit ends on an empty page" "Read 6 entries in 3 pages, the last one shorter than 3"
reset_counters
GET_BODY="${SEVEN}" RULES="$(rules 'limit=3&offset=0' "${P1}" 'limit=3&offset=3' "${EMPTY}")" run 02.files_GET_list.sh
expect "02: a folder that changes while it is read is exit 1" "${RC}" "1"
has "02: and it says so" "The pages held 3 entries and the unpaged answer 7: the folder changed while it was read."
STATUS_GET=404 GET_BODY="${ERR_404}" run 02.files_GET_list.sh
expect "02: a folder that is not there is exit 1, with one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "02: and it says to run 01" "There is no folder example_uc_lists. Run 01.files_POST_location.sh first."
GET_BODY="$(body notfolder '{"name":"john"}')" run 02.files_GET_list.sh
expect "02: an answer with no files and self is exit 1" "${RC}" "1"
has "02: and it says it is not the list of a folder" "The answer has no files and self: it is not the list of a folder."
reset_counters
STUB_STATUS_GET_SEQ="200 200 400" GET_BODY="${SEVEN}" RULES="$(rules 'limit=3&offset=0' "${ERR_NEG}")" run 02.files_GET_list.sh
expect "02: a page that is refused is exit 1" "${RC}" "1"
has "02: with the offset and the reason" "GET /files/example_uc_lists with limit=3 and offset=0: HTTP 400"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 200 400" GET_BODY="${SEVEN}" RULES="$(rules 'limit=3&offset=0' "${P1}" 'limit=3&offset=3' "${P2}" 'limit=3&offset=6' "${P3}" 'limit=0' "${ERR_NEG}")" run 02.files_GET_list.sh
expect "02: a limit=0 that is refused is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 200 200 400" GET_BODY="${SEVEN}" RULES="$(rules 'limit=3&offset=0' "${P1}" 'limit=3&offset=3' "${P2}" 'limit=3&offset=6' "${P3}" 'limit=0' "${EMPTY}" 'order=DESC' "${ERR_NEG}")" run 02.files_GET_list.sh
expect "02: a sort that is refused is exit 1" "${RC}" "1"
for bad in 0 x; do
    run 02.files_GET_list.sh "${bad}"
    expect "02: a LIMIT of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
run 02.files_GET_list.sh 1 2
expect "02: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 03 the list of transfers ==="
HUNDRED="$(body hundred "$(array_json 100)")"; TWO="$(body two "$(array_json 2)")"; THREE="$(body three "$(array_json 3)")"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 400 404" GET_BODY="${TWO}" RULES="$(rules 'limit=-1' "${ERR_NEG}" 'limit=abc' "${ERR_404}" 'limit=3&offset=1' "${THREE}")" run 03.transfers_GET_list.sh
expect "03: the list, a limit with an offset, limit=0, then the two limits it refuses" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/transfers GET ${BASE}/transfers?limit=3&offset=1 GET ${BASE}/transfers?limit=0 GET ${BASE}/transfers?limit=-1 GET ${BASE}/transfers?limit=abc "
has "03: a plain array, with no count" "The answer is a plain array of 2 entries, no wrapper and no count."
has "03: newest first, with the first and the last start time" "Newest first: from Fri, 30 Oct 2026 08:00:59 +0200 down to Fri, 30 Oct 2026 08:00:58 +0200."
hasnt "03: a short list is not said to be the default page" "default page of 100"
has "03: the limit and the offset give that many" "limit=3&offset=1: HTTP 200, 3 entries"
has "03: limit=0 is the default page here" "limit=0: HTTP 200, 2 entries: the default page again, not none"
has "03: limit=-1 is 400 with its reason" "limit=-1: HTTP 400, Parameter should be a positive number or 0."
has "03: limit=abc is 404" "limit=abc: HTTP 404, HTTP 404 Not Found"
reset_counters
GET_BODY="${HUNDRED}" run 03.transfers_GET_list.sh
has "03: a hundred entries is said to be the default page, and that there may be more" "That is the default page of 100. There may be more: ask with an offset."
reset_counters
STUB_STATUS_GET_SEQ="200 403" GET_BODY="${NOT_ALLOWED}" run 03.transfers_GET_list.sh
expect "03: an account that may not use transfers is exit 3, after the one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "3:1"
has "03: and it says why" "403: the account may not use the transfers web service"
reset_counters
STUB_STATUS_GET_SEQ="200 500" GET_BODY="${ERR_404}" run 03.transfers_GET_list.sh
expect "03: any other refusal is exit 1" "${RC}" "1"
GET_BODY="${SEVEN}" run 03.transfers_GET_list.sh
expect "03: an answer that is not a plain array is exit 1" "${RC}" "1"
has "03: and it says so" "The answer is not a plain array."
reset_counters
STUB_STATUS_GET_SEQ="200 200 400" GET_BODY="${TWO}" RULES="$(rules 'limit=3&offset=1' "${ERR_NEG}")" run 03.transfers_GET_list.sh
expect "03: a paged call that is refused is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 400" GET_BODY="${TWO}" RULES="$(rules 'limit=0' "${ERR_NEG}")" run 03.transfers_GET_list.sh
expect "03: a limit=0 that is refused is exit 1" "${RC}" "1"
reset_counters
GET_BODY="${TWO}" run 03.transfers_GET_list.sh 5
expect "03: LIMIT is the one in the paged call" "$(ucalls | sed -n 2p)" "GET ${BASE}/transfers?limit=5&offset=1"
for bad in 0 x; do
    run 03.transfers_GET_list.sh "${bad}"
    expect "03: a LIMIT of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
run 03.transfers_GET_list.sh 1 2
expect "03: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 04 the small lists ==="
BOOK="$(body book '[{"displayName":"LDAP","type":"Group"},{"displayName":"Local","type":"Group"},{"displayName":"ann","type":"User"}]')"
ONE_ENTRY="$(body oneentry '[{"displayName":"LDAP","type":"Group"}]')"
SECOND="$(body second '[{"displayName":"Local","type":"Group"}]')"
QUESTIONS="$(body questions '["Q1?","Q2?","Q3?","Q4?"]')"
small_rules() { rules 'secretQuestions' "${QUESTIONS}" 'limit=1&offset=1' "${SECOND}" 'limit=1' "${ONE_ENTRY}" 'myself/addressBook' "${BOOK}"; }
RULES="$(small_rules)" run 04.addressBook_GET.sh
expect "04: the address book, with a limit, with a limit and an offset, the questions, the questions with a limit" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/myself/addressBook GET ${BASE}/myself/addressBook?limit=1 GET ${BASE}/myself/addressBook?limit=1&offset=1 GET ${BASE}/secretQuestions GET ${BASE}/secretQuestions?limit=2 "
RULES="$(small_rules)" run 04.addressBook_GET.sh
has "04: shows the address book as a plain array and what is in it" "A plain array of 3 entries, no count: LDAP (Group), Local (Group), ann (User)"
has "04: the address book takes a limit" "limit=1: HTTP 200, 1 entries: the address book takes a limit."
has "04: and an offset" "limit=1&offset=1: HTTP 200, 1 entries, the first is Local."
has "04: the questions are text" "A plain array of 4 questions, as text."
has "04: and take no limit" "limit=2: HTTP 200, 4 entries. This list takes no limit."
hasnt "04: with no remark when the list is the same" "does honour a limit here"
RULES="$(rules 'secretQuestions?limit=2' "$(body two_q '["Q1?","Q2?"]')" 'secretQuestions' "${QUESTIONS}" 'limit=1&offset=1' "${SECOND}" 'limit=1' "${ONE_ENTRY}" 'myself/addressBook' "${BOOK}")" run 04.addressBook_GET.sh
has "04: a limit that is honoured on the questions is said" "(It gave 4 before, so this release does honour a limit here.)"
RULES="$(rules 'limit=1&offset=1' "${SECOND}" 'limit=1' "${BOOK}" 'myself/addressBook' "${BOOK}")" run 04.addressBook_GET.sh
expect "04: a limit=1 that gives more than one entry is exit 1" "${RC}" "1"
has "04: and it says what was expected" "limit=1 was expected to give one entry."
RULES="$(rules 'limit=1&offset=1' "$(body none '[]')" 'limit=1' "$(body none '[]')" 'secretQuestions' "${QUESTIONS}" 'myself/addressBook' "$(body none '[]')")" run 04.addressBook_GET.sh
expect "04: an address book with nothing in it is not an error" "${RC}" "0"
GET_BODY="${SEVEN}" run 04.addressBook_GET.sh
expect "04: an address book that is not a plain array is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 500" GET_BODY="${ERR_404}" run 04.addressBook_GET.sh
expect "04: a refused address book is exit 1, after one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 500" RULES="$(small_rules)" run 04.addressBook_GET.sh
expect "04: a refused limit=1 is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 500" RULES="$(small_rules)" run 04.addressBook_GET.sh
expect "04: a refused offset is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 500" RULES="$(small_rules)" run 04.addressBook_GET.sh
expect "04: a refused list of questions is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 500" RULES="$(small_rules)" run 04.addressBook_GET.sh
expect "04: a refused list of questions with a limit is exit 1" "${RC}" "1"
RULES="$(rules 'secretQuestions' "${SEVEN}" 'myself/addressBook' "${BOOK}" 'limit=1&offset=1' "${SECOND}" 'limit=1' "${ONE_ENTRY}")" run 04.addressBook_GET.sh
expect "04: questions that are not a plain array are exit 1" "${RC}" "1"
run 04.addressBook_GET.sh now
expect "04: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 05 fields= is not offered ==="
ME="$(body me '{"name":"john","uid":"1","gid":"1","type":"user"}')"
ME_NARROW="$(body me_narrow '{"name":"john"}')"
FILE_ONE="$(body fileone "$(files_json 1 1)")"
FILE_ENTRY="$(body fileentry '{"files":[{"fileName":"lst_01.txt","isDirectory":false,"size":45}],"self":{"fileName":"example_uc_lists"}}')"
fields_rules() { rules 'transfers' "${THREE}" 'myself' "${ME}" 'files/example_uc_lists' "${FILE_ENTRY}"; }
RULES="$(fields_rules)" run 05.fields_not_offered.sh
expect "05: the folder, the account and the transfers, each with and without fields=" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${F} GET ${F}?fields=fileName GET ${BASE}/myself GET ${BASE}/myself?fields=name GET ${BASE}/transfers?limit=1 GET ${BASE}/transfers GET ${BASE}/transfers?fields=filename "
has "05: counts the fields of a file entry" "the first entry has 3 fields, and 3 with fields=fileName."
has "05: counts those of the account" "the first entry has 4 fields, and 4 with fields=name."
has "05: and those of a transfer" "the first entry has 5 fields, and 5 with fields=filename."
has "05: says it made no difference" "fields= made no difference."
has "05: and what to do about it" "Ask for the fields you need and read those, but expect the whole entry, whatever fields= says."
RULES="$(rules 'fields=name' "${ME_NARROW}" 'transfers' "${THREE}" 'myself' "${ME}" 'files/example_uc_lists' "${FILE_ENTRY}")" run 05.fields_not_offered.sh
expect "05: an answer that is narrower with fields= is exit 1" "${RC}" "1"
has "05: and it says the release offers it" "fields= changed the answer: this release offers it. This use case is out of date."
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 403" RULES="$(fields_rules)" run 05.fields_not_offered.sh
expect "05: an account that may not use transfers has that part skipped, and the rest is exit 0" "${RC}:$(ucalls | grep -c transfers)" "0:1"
has "05: with the reason" "GET /transfers is skipped:"
reset_counters
STUB_STATUS_GET_SEQ="200 500" RULES="$(fields_rules)" run 05.fields_not_offered.sh
expect "05: a first read that is refused is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 500" RULES="$(fields_rules)" run 05.fields_not_offered.sh
expect "05: a call with fields= that is refused is exit 1" "${RC}" "1"
has "05: with its code" "GET /files/example_uc_lists?fields=fileName: HTTP 500"
run 05.fields_not_offered.sh now
expect "05: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 06 counting without a totalCount ==="
T1="$(body t1 "$(array_json 2)")"; T2="$(body t2 "$(array_json 2)")"; T3="$(body t3 '[]')"; TONE="$(body tone "$(array_json 1)")"
count_rules() { rules 'transfers?limit=1' "${TONE}" 'transfers?limit=2&offset=0' "${T1}" 'transfers?limit=2&offset=2' "${T2}" 'transfers?limit=2&offset=4' "${T3}" 'limit=2&offset=0' "${P1}" 'limit=2&offset=3' "${P3}" 'files/example_uc_lists' "$(body three_files "$(files_json 1 3)")"; }
RULES="$(rules 'transfers?limit=1' "${TONE}" 'transfers?limit=2&offset=0' "${T1}" 'transfers?limit=2&offset=2' "${T2}" 'transfers?limit=2&offset=4' "${T3}" 'limit=2&offset=0' "$(body f1 "$(files_json 1 2)")" 'limit=2&offset=2' "$(body f2 "$(files_json 3 1)")" 'files/example_uc_lists' "$(body three_files "$(files_json 1 3)")")" run 06.counting_without_totalCount.sh 2
expect "06: the folder whole, its pages, then the transfers by their pages (the last empty)" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${F} GET ${F}?limit=2&offset=0 GET ${F}?limit=2&offset=2 GET ${BASE}/transfers?limit=1 GET ${BASE}/transfers?limit=2&offset=0 GET ${BASE}/transfers?limit=2&offset=2 GET ${BASE}/transfers?limit=2&offset=4 "
has "06: counts the files and says how" "Files in example_uc_lists: 3, counted in 2 calls of up to 2."
has "06: and the transfers" "Transfers: 4, counted in 3 calls of up to 2."
hasnt "06: no remark about 100 for a small page size" "default page"
reset_counters
RULES="$(rules 'transfers?limit=100&offset=0' "${HUNDRED}" 'transfers?limit=100&offset=100' "$(body five "$(array_json 5)")" 'transfers?limit=1' "${TONE}" 'files/example_uc_lists' "${SEVEN}")" run 06.counting_without_totalCount.sh
expect "06: the default PAGE_SIZE is 100" "$(ucalls | sed -n 2p)" "GET ${F}?limit=100&offset=0"
has "06: more than 100 transfers is counted, and what a single call would have missed" "Transfers: 105, counted in 2 calls of up to 100."
has "06: with the number it would have missed" "a client that read one call would have missed 5."
reset_counters
RULES="$(rules 'transfers?limit=50&offset=0' "$(body fifty "$(array_json 50)")" 'transfers?limit=1' "${TONE}" 'files/example_uc_lists' "${SEVEN}")" run 06.counting_without_totalCount.sh 50
hasnt "06: a page size of 50 that reads 50 transfers is not said to have missed any" "would have missed"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 403" GET_BODY="${SEVEN}" RULES="$(rules 'limit=100' "${SEVEN}" 'transfers' "${NOT_ALLOWED}" 'files/example_uc_lists' "${SEVEN}")" run 06.counting_without_totalCount.sh
expect "06: an account that may not use transfers counts the files alone, exit 0" "${RC}" "0"
has "06: and says why the transfers are not counted" "Transfers are not counted:"
has "06: the files are counted" "Files in example_uc_lists: 7, counted in 1 calls of up to 100."
reset_counters
RULES="$(rules 'limit=2&offset=0' "$(body f1 "$(files_json 1 2)")" 'limit=2&offset=2' "${EMPTY}" 'files/example_uc_lists' "$(body three_files "$(files_json 1 3)")")" run 06.counting_without_totalCount.sh 2
expect "06: a folder whose paged count is not the unpaged one is exit 1" "${RC}" "1"
has "06: and it says so" "The unpaged answer has 3 entries: the folder changed while it was counted."
STATUS_GET=404 GET_BODY="${ERR_404}" run 06.counting_without_totalCount.sh
expect "06: a folder that cannot be read is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 500" GET_BODY="${SEVEN}" run 06.counting_without_totalCount.sh
expect "06: a page of files that is refused is exit 1" "${RC}" "1"
has "06: and it says the count stopped" "Counting the files stopped (HTTP 500) after 0 pages."
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 500" GET_BODY="${SEVEN}" RULES="$(rules 'transfers' "${ERR_404}" 'files/example_uc_lists' "${SEVEN}")" run 06.counting_without_totalCount.sh
expect "06: a refused read of the transfers is exit 1" "${RC}" "1"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 500" RULES="$(rules 'transfers' "${TWO}" 'files/example_uc_lists' "${SEVEN}")" run 06.counting_without_totalCount.sh
expect "06: a page of transfers that is refused is exit 1" "${RC}" "1"
has "06: and it says the count stopped" "Counting the transfers stopped (HTTP 500) after 0 pages."
for bad in 0 x; do
    run 06.counting_without_totalCount.sh "${bad}"
    expect "06: a PAGE_SIZE of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
run 06.counting_without_totalCount.sh 1 2
expect "06: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 99 the cleanup ==="
MIXED="$(body mixed '{"files":[{"fileName":"lst_01.txt"},{"fileName":"keep.txt"},{"fileName":"lst_02.txt"},{"fileName":"lst_2.txt"}],"self":{}}')"
reset_counters
STUB_STATUS_DELETE=204 GET_BODY="${MIXED}" run 99.cleanup_DELETE.sh
expect "99: deletes the files that are named lst_NN.txt, then the folder, then ends the session" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${F} DELETE ${F}/lst_01.txt DELETE ${F}/lst_02.txt DELETE ${F} DELETE ${BASE}/myself "
has "99: says how many files" "Deleted 2 files from example_uc_lists."
has "99: and the folder" "The folder example_uc_lists was deleted."
has "99: and that it is clean" "Cleaned up."
expect "99: the jar is gone" "$([ -e "${UC}/session.cookie.jar" ] && echo left || echo none)" "none"
STUB_STATUS_DELETE=403 GET_BODY="${MIXED}" run 99.cleanup_DELETE.sh
expect "99: a folder that cannot be deleted is exit 1" "${RC}" "1"
has "99: with the reason to look at" "could not be deleted (HTTP 403): is anything else in it?"
has "99: a file that cannot be deleted is said" "The file example_uc_lists/lst_01.txt could not be deleted (HTTP 403): delete it by hand."
has "99: it still cleans up" "Cleaned up."
reset_counters
STUB_STATUS_GET_SEQ="200 404" GET_BODY="${ERR_404}" run 99.cleanup_DELETE.sh
expect "99: a folder that is not there is not an error" "${RC}:$(ucalls | grep -c DELETE)" "0:1"
has "99: and it says so" "There is no folder example_uc_lists: nothing to delete."
reset_counters
STUB_STATUS_GET_SEQ="200 500" GET_BODY="${ERR_404}" run 99.cleanup_DELETE.sh
expect "99: a folder that cannot be read is exit 1" "${RC}" "1"
has "99: and says to delete it by hand" "Could not read the folder example_uc_lists (HTTP 500): delete it by hand."
rm -f "${UC}/session.cookie.jar" "${UC}/state.local.csrf"
reset_counters
OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_COUNTER="${WORK}/ctr" STUB_CURL_STATUS=200 STUB_CURL_STATUS_GET=404 STUB_CURL_GET_BODY="${ERR_404}" STUB_CURL_PRINT_CODE=1 bash ./99.cleanup_DELETE.sh 2>&1); RC=$?
expect "99: with no session it logs in, so it can be run twice (exit 0)" "${RC}" "0"
run 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 00 run_all ==="
reset_counters
STUB_STATUS_GET_SEQ="200 500" STUB_STATUS_DELETE=204 GET_BODY="${ERR_404}" run 00.run_all.sh
expect "00: a failing step is exit 1" "${RC}" "1"
has "00: says which step failed" "01.files_POST_location failed."
hasnt "00: and does not go on" "=== 02.files_GET_list ==="
has "00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="
run 00.run_all.sh 0
expect "00: a wrong COUNT is exit 2 at once, nothing sent" "${RC}:$(ncalls)" "2:0"
has "00: with the usage" "Usage: ./00.run_all.sh [COUNT] [LIMIT]"
run 00.run_all.sh 7 0
expect "00: a wrong LIMIT is exit 2 at once, nothing sent" "${RC}:$(ncalls)" "2:0"
run 00.run_all.sh 1 2 3
expect "00: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"
# a whole run, for an account that may not use the transfers web service: 03 is skipped, 05 and 06 say so and go on
reset_counters
WHOLE_RULES="$(rules 'limit=abc' "${ERR_404}" 'limit=-1' "${SEVEN}" 'order=DESC' "${DESC}" 'limit=0' "${EMPTY}" 'limit=3&offset=0' "${P1}" 'limit=3&offset=3' "${P2}" 'limit=3&offset=6' "${P3}" \
  'secretQuestions' "${QUESTIONS}" 'addressBook?limit=1&offset=1' "${SECOND}" 'addressBook?limit=1' "${ONE_ENTRY}" 'myself/addressBook' "${BOOK}" 'transfers' "${NOT_ALLOWED}" 'files/example_uc_lists' "${SEVEN}")"
GETS="200 404 200  200 200 200 200 200 200 200 200 404 200  200 403  200 200 200 200 200 200  200 200 200 200 200 403  200 200 200 403  200 200"
RULES="${WHOLE_RULES}" STUB_STATUS_GET_SEQ="${GETS}" STUB_STATUS_POST=201 STUB_STATUS_DELETE=204 GET_BODY="${SEVEN}" run 00.run_all.sh
expect "00: six steps and the cleanup, with 03 skipped: exit 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== ')" "0:7"
has "00: an exit 3 is a skip, with its reason" "03.transfers_GET_list was skipped: the account may not use this part."
hasnt "00: and not a failure" "03.transfers_GET_list failed."
has "00: the cleanup ends it" "Cleaned up."

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}"/08-lists-and-paging/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/API 2.0\/bash\/[^ ,;]*).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "${s}")"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_enduser_usecase_08: FAIL"; exit 1; fi
echo "test_bash_enduser_usecase_08: PASS"
