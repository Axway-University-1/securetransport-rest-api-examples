#!/bin/bash
# ==============================================================================
# Run Admin/UseCases/06-lists-paging-and-fields against a stub curl, and check the calls each script makes:
# the method, the URL and the query it builds (limit, offset, fields, the filter), the body of a POST, the headers,
# what it prints about the answers, and its exit code.
#
# 01 the default page, limit=0, limit=1, and a 200 that is not a list; 02 the paging walk (the pages it asks for, the
# stop at totalCount with no empty last call, the list that changes while it is read, a refused page, a page size of
# 0); 03 fields= with the refusals that are the expected answer; 04 HEAD 200, 404 and 405; 05 the business units made
# and the Location header checked against the name, a second POST refused; 06 the filter with its totalCount, the
# paged and narrowed call, and a filter that finds nothing; 99 the exact names, 404 as "not there", twice; 00 failing
# fast, still cleaning up, and a whole run.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_06"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl" && chmod +x "${WORK}/bin/curl"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/06-lists-paging-and-fields" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
UC="${WORK}/tree/UseCases/06-lists-paging-and-fields"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
RULE_N=0
rules() {
    local out="${WORK}/rules_$((++RULE_N)).tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
# list_json TOTAL NAME...: an Admin list with those entries (returnCount is how many names are given)
list_json() {
    local total="$1"; shift
    jq -cn --argjson total "${total}" '{resultSet: {returnCount: ($ARGS.positional | length), totalCount: $total}, result: [$ARGS.positional[] | {name: ., type: "user"}]}' --args "$@"
}
reset_counters() { rm -f "${WORK}"/ctr.*; }

# run SCRIPT [PARAMS]: with a session jar in place (the stub writes none). GET_BODY and RULES set the answers.
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
hdrs_of() { printf '%s\n' "${OUT}" | awk -v M="$1" '/^HEADER:/ {b = b $0 "\n"} /^METHOD:/ {if ($2 == M) r = b; b = ""} END {printf "%s", r}' | sed 's/^HEADER: //'; }

THREE="$(body three "$(list_json 3 ann bob cy)")"
ERR_LIMIT="$(body err_limit '{"message":"Error validating request","validationErrors":["The limit should be a positive number or 0."]}')"
OPTION_100="$(body option '{"result":[{"name":"Webservices.EntriesPerPage","values":["100"]}]}')"

echo "=== 01 the default page ==="
GET_BODY="${THREE}" RULES="$(rules EntriesPerPage "${OPTION_100}" 'limit=1' "$(body one "$(list_json 3 ann)")")" run 01.list_default_GET.sh
expect "01: the list, the page-size setting, then limit=0 and limit=1" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts GET ${BASE}/configurations/options?name=Webservices.EntriesPerPage GET ${BASE}/accounts?limit=0 GET ${BASE}/accounts?limit=1 "
has "01: says what the answer holds" "returnCount 3, totalCount 3."
has "01: and that a whole list came in one answer" "The whole list came in this one answer."
has "01: names the setting and its value" "Webservices.EntriesPerPage: 100."
has "01: limit=0 is the default page" "limit=0 does not mean all."
has "01: limit=1 counts, with totalCount and not returnCount" "returnCount 1, totalCount 3: to count a list"
GET_BODY="$(body page '{"resultSet":{"returnCount":2,"totalCount":5},"result":[{"name":"a"},{"name":"b"}]}')" run 01.list_default_GET.sh servers
expect "01: a RESOURCE is read from its own path" "$(ucalls | head -1)" "GET ${BASE}/servers"
has "01: a short page says it is a page and where the rest is" "This is one page, the first 2 of 5. 02.paging_walk.sh reads the rest."
GET_BODY="$(body not_list '{"loginName":"admin"}')" run 01.list_default_GET.sh myself
expect "01: an answer that is not a list is exit 1, with nothing more asked" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "01: and it says so" "The answer has no resultSet and result: /myself is not an Admin list."
STATUS_GET=400 GET_BODY="${ERR_LIMIT}" run 01.list_default_GET.sh
expect "01: a refused list is exit 1" "${RC}" "1"
has "01: with the code and the reason" "The limit should be a positive number or 0."
reset_counters
STUB_STATUS_GET_SEQ="200 200 403 200 200" GET_BODY="${THREE}" run 01.list_default_GET.sh
has "01: a setting that cannot be read is said with its code, and the default is named" "Could not read Webservices.EntriesPerPage (HTTP 403). The default page is 100 unless an administrator changed it."
expect "01: ... exit 0" "${RC}" "0"
run 01.list_default_GET.sh 'bad resource!'
expect "01: a RESOURCE that is not a path is exit 2, nothing sent (not even the check of the session)" "${RC}:$(ncalls)" "2:0"
has "01: with the reason and the usage" "RESOURCE is 'bad resource!'"
has "01: and the usage" "Usage: ./01.list_default_GET.sh [RESOURCE]"
run 01.list_default_GET.sh accounts servers
expect "01: two parameters is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "01: and it says how many were given and how many are taken" "2 parameters were given, and at most 1 is taken: RESOURCE."

echo "=== 02 the paging walk ==="
PAGE_A="$(body pa "$(list_json 5 a b)")"; PAGE_B="$(body pb "$(list_json 5 c d)")"; PAGE_C="$(body pc "$(list_json 5 e)")"; PAST="$(body past "$(list_json 5)")"
RULES="$(rules 'offset=0' "${PAGE_A}" 'offset=2' "${PAGE_B}" 'offset=4' "${PAGE_C}" 'offset=5' "${PAST}")" run 02.paging_walk.sh accounts 2
expect "02: asks page after page and then one past the end, no more" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts?limit=2&offset=0 GET ${BASE}/accounts?limit=2&offset=2 GET ${BASE}/accounts?limit=2&offset=4 GET ${BASE}/accounts?limit=2&offset=5 "
has "02: shows each page" "page 2: offset 2, 2 entries"
has "02: the last page is the short one" "page 3: offset 4, 1 entries"
has "02: adds up what it read and compares it with totalCount" "Read 5 entries in 3 pages. totalCount said 5."
has "02: shows that a page past the end is a 200 with nothing in it" "A page past the end (offset 5): HTTP 200, 0 entries, totalCount 5."
FOUR_A="$(body fa "$(list_json 4 a b)")"; FOUR_B="$(body fb "$(list_json 4 c d)")"; FOUR_PAST="$(body fpast "$(list_json 4)")"
RULES="$(rules 'offset=0' "${FOUR_A}" 'offset=2' "${FOUR_B}" 'offset=4' "${FOUR_PAST}")" run 02.paging_walk.sh accounts 2
expect "02: a list that is a multiple of the page size costs no empty last call before the check past the end" "${RC}:$(ucalls | wc -l | tr -d ' ')" "0:3"
RULES="$(rules 'offset=0' "${PAGE_A}" 'offset=2' "${PAST}" 'offset=5' "${PAST}")" run 02.paging_walk.sh accounts 2
expect "02: a list that shrinks while it is read stops on the empty page and is exit 1" "${RC}:$(ucalls | head -2 | tail -1)" "1:GET ${BASE}/accounts?limit=2&offset=2"
has "02: and says what happened" "The pages held 2 entries and totalCount said 5: the list changed while it was read. Read it again."
GET_BODY="${THREE}" run 02.paging_walk.sh
expect "02: the defaults are accounts and 5 entries a page" "$(ucalls | head -1)" "GET ${BASE}/accounts?limit=5&offset=0"
STATUS_GET=400 GET_BODY="${ERR_LIMIT}" run 02.paging_walk.sh accounts 2
expect "02: a page that is refused is exit 1, after that one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "02: and the code and the reason are shown with the offset" "GET /accounts with limit=2 and offset=0: HTTP 400"
has "02: the reason" "The limit should be a positive number or 0."
for bad in 0 abc -3 2.5; do
    run 02.paging_walk.sh accounts "${bad}"
    expect "02: a PAGE_SIZE of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "02: 0 is explained, it is not 'all'" "PAGE_SIZE is '2.5': it must be a whole number of 1 or more. (0 is not 'all'"
run 02.paging_walk.sh 'a b'
expect "02: a RESOURCE that is not a path is exit 2" "${RC}:$(ncalls)" "2:0"
run 02.paging_walk.sh accounts 2 3
expect "02: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 03 fields ==="
FULL="$(body full '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"type":"user","name":"ann","homeFolder":"/h","contact":{}}]}')"
NARROW="$(body narrow '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"type":"user","name":"ann"}]}')"
REFUSED_NOSUCH="$(body r1 '{"message":"Error validating request","validationErrors":["Field nosuch does not exist."]}')"
SERVER_ONE="$(body sv '{"resultSet":{"returnCount":1,"totalCount":1},"result":[{"protocol":"http","serverName":"S3 Only"}]}')"
REFUSED_PROTOCOL="$(body r2 '{"message":"Error validating request","validationErrors":["Field protocol does not exist."]}')"
fields_rules() { rules 'fields=nosuch' "${REFUSED_NOSUCH}" 'fields=protocol' "${REFUSED_PROTOCOL}" 'fields=serverName' "${SERVER_ONE}" 'fields=name' "${NARROW}" 'fields=contact.email,name' "${NARROW}"; }
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 400 200 400" GET_BODY="${FULL}" RULES="$(fields_rules)" run 03.fields_GET.sh
expect "03: the entry whole, with fields=name, with a field that does not exist, then /servers twice" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts?limit=1 GET ${BASE}/accounts?limit=1&fields=name GET ${BASE}/accounts?limit=1&fields=nosuch GET ${BASE}/servers?limit=1&fields=serverName GET ${BASE}/servers?limit=1&fields=protocol "
has "03: counts the fields of the whole entry and names them" "one entry has 4 fields: contact, homeFolder, name, type"
has "03: and of the narrow one" "now it has 2 fields: name, type"
has "03: shows the refusal and its reason" "Field nosuch does not exist."
has "03: shows that protocol is in the answer though it was not asked for" 'the entry is {"protocol":"http","serverName":"S3 Only"}: protocol is in it'
has "03: shows that protocol cannot be asked for" "Field protocol does not exist."
has "03: and what to do" "leave it out of fields= and read it from the answer."
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 400 200 400" GET_BODY="${FULL}" RULES="$(fields_rules)" run 03.fields_GET.sh accounts contact.email,name
expect "03: the fields that were given are the ones asked for" "$(ucalls | sed -n 2p)" "GET ${BASE}/accounts?limit=1&fields=contact.email,name"
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 200 200 400" GET_BODY="${FULL}" RULES="$(fields_rules)" run 03.fields_GET.sh
expect "03: a field that does not exist and is answered 200 is exit 1" "${RC}" "1"
has "03: and it says what was expected" "The server was expected to refuse it with 400."
reset_counters
STUB_STATUS_GET_SEQ="200 200 200 400 200 200" GET_BODY="${FULL}" RULES="$(fields_rules)" run 03.fields_GET.sh
expect "03: protocol answered 200 is exit 1" "${RC}" "1"
has "03: and it says what was expected" "The server was expected to refuse protocol with 400."
reset_counters
STUB_STATUS_GET_SEQ="400" GET_BODY="${ERR_LIMIT}" run 03.fields_GET.sh
expect "03: a first read that is refused is exit 1, after that one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
GET_BODY="$(body empty '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')" run 03.fields_GET.sh
expect "03: an empty list is exit 1, with nothing more asked" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "03: and it says so" "The list /accounts is empty: there is no entry to look at."
run 03.fields_GET.sh accounts 'name;x'
expect "03: FIELDS that are not names are exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
has "03: with the usage" "Usage: ./03.fields_GET.sh [RESOURCE] [FIELDS]"
run 03.fields_GET.sh '../x'
expect "03: a RESOURCE that is not a path is exit 2" "${RC}:$(ncalls)" "2:0"
run 03.fields_GET.sh a b c
expect "03: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 04 HEAD ==="
FIRST_NAME="$(body first "$(list_json 3 'john smith')")"
reset_counters
STUB_STATUS_HEAD_SEQ="200 404 405" GET_BODY="${FIRST_NAME}" run 04.head_exists.sh
expect "04: the first name from the list, HEAD of it, of a name that is not there, and of deniedUsers" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts?limit=1&fields=name HEAD ${BASE}/accounts/john%20smith HEAD ${BASE}/accounts/john%20smith_example_missing HEAD ${BASE}/deniedUsers/example_lst_none "
has "04: 200 is there" "200: it is there."
has "04: 404 is not there" "404: it is not there."
has "04: 405 is not 'not there'" "405: this resource has no HEAD of one name. It does not say 'not there'."
reset_counters
STUB_STATUS_HEAD_SEQ="200 404 405" run 04.head_exists.sh servers bob
expect "04: a NAME that is given is asked for with no list call" "${RC}:$(ucalls | head -1)" "0:HEAD ${BASE}/servers/bob"
reset_counters
STUB_STATUS_HEAD_SEQ="404 404 405" run 04.head_exists.sh accounts bob
expect "04: a name the list gave that is 404 is exit 1" "${RC}" "1"
has "04: with the reason" "An object the list gave should be 200."
reset_counters
STUB_STATUS_HEAD_SEQ="200 200 405" run 04.head_exists.sh accounts bob
expect "04: a name that is not there and is 200 is exit 1" "${RC}" "1"
has "04: with the reason" "A name that is not there should be 404."
reset_counters
STUB_STATUS_HEAD_SEQ="200 404 200" run 04.head_exists.sh accounts bob
expect "04: a deniedUsers that is not 405 is said, and is not an error" "${RC}" "0"
has "04: it says what it answered" "(deniedUsers answered 200; it answered 405 on the lab this was written on.)"
GET_BODY="$(body noname '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')" run 04.head_exists.sh
expect "04: a list with no name to ask for is exit 1, with no HEAD" "${RC}:$(ucalls | grep -c HEAD)" "1:0"
has "04: and it says to give NAME" "has no entry with a name to ask for. Give NAME."
STATUS_GET=400 GET_BODY="${ERR_LIMIT}" run 04.head_exists.sh
expect "04: a list that is refused is exit 1" "${RC}" "1"
run 04.head_exists.sh 'a b'
expect "04: a RESOURCE that is not a path is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 04.head_exists.sh accounts bob extra
expect "04: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 05 the objects and the Location header ==="
reset_counters
STUB_STATUS_POST_SEQ="201 201 201 201 201 400" STUB_LOCATION_PREFIX=example_lst_ GET_BODY="$(body unit '{"name":"example_lst_1"}')" run 05.location_POST.sh
expect "05: five POSTs, a GET of the first address, and a sixth POST of the first name" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:POST ${BASE}/businessUnits POST ${BASE}/businessUnits POST ${BASE}/businessUnits POST ${BASE}/businessUnits POST ${BASE}/businessUnits GET ${BASE}/businessUnits/example_lst_1 POST ${BASE}/businessUnits "
expect "05: the first body is a name and a base folder under /home" "$(payload 1 | jq -c .)" '{"name":"example_lst_1","baseFolder":"/home/example_lst_1"}'
expect "05: the fifth is example_lst_5" "$(payload 5 | jq -r .name)" "example_lst_5"
expect "05: the last POST is the first name again" "$(payload 6 | jq -r .name)" "example_lst_1"
expect "05: a POST carries accept, Referer, the content type and the csrfToken" "$(hdrs_of POST | grep -cE '^(Referer: |Content-Type: application/json|accept: \*/\*|csrfToken:)')" "4"
has "05: prints the Location of each" "Location: ${BASE}/businessUnits/example_lst_3"
has "05: says a 201 has no body" "Body: 0 bytes. A 201 has no body; the address is the answer."
has "05: reads the first one back by its address" "GET of that address: HTTP 200, the unit is example_lst_1."
has "05: shows that the second POST of a name is refused" "The same POST again (example_lst_1): HTTP 400"
reset_counters
STUB_STATUS_POST_SEQ="201 201" STUB_LOCATION_PREFIX=example_lst_ GET_BODY="$(body unit)" run 05.location_POST.sh 2
expect "05: COUNT is how many are made" "$(ucalls | grep -c '^POST')" "3"
reset_counters
STUB_STATUS_POST_SEQ="201 201 400" STUB_LOCATION_PREFIX=example_lst_ run 05.location_POST.sh
expect "05: a POST that is refused stops it with exit 1, and no more are made" "${RC}:$(ucalls | grep -c '^POST')" "1:3"
has "05: with the reason to remove what is left" "Nothing more was made. If example_lst_3 is left from an earlier run, remove it with 99.cleanup_DELETE.sh."
reset_counters
STUB_STATUS_POST_SEQ="201" STUB_LOCATION_PREFIX=other_ run 05.location_POST.sh 1
expect "05: a Location that does not end with the name is exit 1" "${RC}" "1"
has "05: with the reason" "The Location does not end with /businessUnits/example_lst_1."
reset_counters
STUB_STATUS_POST_SEQ="201 201" STUB_LOCATION_PREFIX=example_lst_ run 05.location_POST.sh 1
expect "05: a second POST of the same name that is made is exit 1" "${RC}" "1"
has "05: and it says what was expected" "The server made a second unit of the same name. It was expected to refuse."
reset_counters
STUB_STATUS_POST_SEQ="201" STUB_LOCATION_PREFIX=example_lst_ STATUS_GET=404 run 05.location_POST.sh 1
expect "05: an address that cannot be read is exit 1" "${RC}" "1"
for bad in 0 10 x; do
    run 05.location_POST.sh "${bad}"
    expect "05: a COUNT of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "05: with the range" "COUNT is 'x': it must be a whole number from 1 to 9."
run 05.location_POST.sh 2 3
expect "05: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 06 filters, paging and fields together ==="
FIVE="$(body five "$(list_json 5 example_lst_1 example_lst_2)")"
SIX="$(body six "$(list_json 6 Finance)")"
NOTHING="$(body nothing "$(list_json 0)")"
PAGE="$(body pagebody "$(list_json 5 example_lst_3 example_lst_4)")"
filter_rules() { rules 'name=example_lst_nothing_*' "$1" 'name=EXAMPLE_LST_*' "${FIVE}" 'limit=2&offset=2' "${PAGE}" 'name=example_lst_*' "${FIVE}" 'businessUnits?limit=1' "${SIX}"; }
RULES="$(filter_rules "${NOTHING}")" run 06.filters_GET.sh
expect "06: the filter, no filter, the page with fields, a filter with no match, the capitals" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/businessUnits?name=example_lst_*&limit=1 GET ${BASE}/businessUnits?limit=1 GET ${BASE}/businessUnits?name=example_lst_*&limit=2&offset=2&fields=name GET ${BASE}/businessUnits?name=example_lst_nothing_*&limit=1 GET ${BASE}/businessUnits?name=EXAMPLE_LST_*&limit=1 "
has "06: shows the total with the filter" "name=example_lst_*: totalCount 5"
has "06: and without it, and says what the filter did" "No filter: totalCount 6. The filter made it 5: totalCount counts what matches."
has "06: shows the page and the names on it" "returnCount 2 of totalCount 5: example_lst_3, example_lst_4"
has "06: a filter that finds nothing is an empty list" "totalCount 0: a filter that finds nothing is an empty list, not an error."
has "06: capitals are the same" "The pattern in capitals: totalCount 5: upper and lower case are the same."
RULES="$(filter_rules "${NOTHING}")" run 06.filters_GET.sh 3
expect "06: PAGE_SIZE sets limit and offset" "$(ucalls | sed -n 3p)" "GET ${BASE}/businessUnits?name=example_lst_*&limit=3&offset=3&fields=name"
RULES="$(rules 'name=example_lst_*' "${NOTHING}")" run 06.filters_GET.sh
expect "06: with no unit of the use case it stops after one call, exit 1" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "06: and says to run 05" "There is no business unit named example_lst_*. Run 05.location_POST.sh first."
RULES="$(filter_rules "$(body some "$(list_json 3 x)")")" run 06.filters_GET.sh
expect "06: a filter that should find nothing and finds some is exit 1" "${RC}" "1"
STATUS_GET=400 GET_BODY="${ERR_LIMIT}" run 06.filters_GET.sh
expect "06: a refused call is exit 1, with the reason" "${RC}" "1"
has "06: the reason" "The limit should be a positive number or 0."
for bad in 0 x; do
    run 06.filters_GET.sh "${bad}"
    expect "06: a PAGE_SIZE of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
run 06.filters_GET.sh 2 3
expect "06: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 99 the cleanup ==="
echo tok77 > "${UC}/state.local.csrf"
reset_counters
STUB_STATUS_DELETE=204 run 99.cleanup_DELETE.sh
expected=""
for n in 1 2 3 4 5 6 7 8 9; do expected="${expected}DELETE ${BASE}/businessUnits/example_lst_${n} "; done
expect "99: deletes example_lst_1 to 9 by name, then ends the session" "${RC}:$(ucalls | tr '\n' ' ')" "0:${expected}DELETE ${BASE}/myself "
has "99: says what it deleted" "The business unit example_lst_9 was deleted."
has "99: and that it is clean" "Cleaned up."
expect "99: a DELETE carries the csrfToken" "$(hdrs_of DELETE | grep -c '^csrfToken: tok77')" "1"
expect "99: the session files are gone" "$([ -e "${UC}/session.cookie.jar" ] || [ -e "${UC}/state.local.csrf" ] && echo left || echo none)" "none"
STATUS_GET=200 STUB_STATUS_DELETE=404 run 99.cleanup_DELETE.sh
expect "99: units that are not there are 404, said nothing about, and it is exit 0" "${RC}" "0"
hasnt "99: nothing is said about a unit that was not there" "business unit example_lst_1"
STUB_STATUS_DELETE=500 run 99.cleanup_DELETE.sh
expect "99: a DELETE that fails is exit 1" "${RC}" "1"
has "99: and it says to delete it by hand" "The business unit example_lst_1 could not be deleted (HTTP 500): delete it by hand."
has "99: it still cleans up" "Cleaned up."
rm -f "${UC}/session.cookie.jar" "${UC}/state.local.csrf"
OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_STATUS=200 STUB_CURL_PRINT_CODE=1 STUB_STATUS_DELETE=404 STUB_COUNTER="${WORK}/ctr" bash ./99.cleanup_DELETE.sh 2>&1); RC=$?
expect "99: with no session it logs in, so it can run twice (exit 0)" "${RC}" "0"
run 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 00 run_all ==="
STATUS_GET=500 GET_BODY="${ERR_LIMIT}" STUB_STATUS_DELETE=404 run 00.run_all.sh
expect "00: a failing step is exit 1" "${RC}" "1"
has "00: says which step failed" "01.list_default_GET failed."
hasnt "00: and does not go on" "=== 02.paging_walk ==="
has "00: and still runs the cleanup" "=== 99.cleanup_DELETE ==="
expect "00: the cleanup deletes the nine names" "$(calls | grep -c '^DELETE .*businessUnits/example_lst_')" "9"
run 00.run_all.sh 'bad resource'
expect "00: a wrong RESOURCE is exit 2 at once, nothing sent, no cleanup" "${RC}:$(ncalls)" "2:0"
has "00: with the usage" "Usage: ./00.run_all.sh [RESOURCE] [PAGE_SIZE]"
run 00.run_all.sh accounts 0
expect "00: a wrong PAGE_SIZE is exit 2 at once, nothing sent" "${RC}:$(ncalls)" "2:0"
run 00.run_all.sh a b c
expect "00: three parameters is exit 2" "${RC}:$(ncalls)" "2:0"
# a whole run: the status of every GET and HEAD in order (each step starts with the check of the session)
reset_counters
GETS="200 200 200 200 200  200 200 200  200 200 200 400 200 400  200 200  200 200  200 200 200 200 200 200  200"
RULES="$(rules 'fields=nosuch' "${REFUSED_NOSUCH}" 'fields=protocol' "${REFUSED_PROTOCOL}" 'fields=serverName' "${SERVER_ONE}" 'name=example_lst_nothing_*' "${NOTHING}" \
      'fields=name' "${NARROW}" 'EntriesPerPage' "${OPTION_100}")" \
  STUB_STATUS_GET_SEQ="${GETS}" STUB_STATUS_HEAD_SEQ="200 404 405" STUB_STATUS_POST_SEQ="201 201 201 201 201 400" STUB_STATUS_DELETE=204 STUB_LOCATION_PREFIX=example_lst_ \
  GET_BODY="$(body whole "$(list_json 3 example_lst_1 example_lst_2 example_lst_3 | jq -c '.result[0].homeFolder = "/h"')")" run 00.run_all.sh
expect "00: all six steps and the cleanup, exit 0" "${RC}:$(printf '%s\n' "${OUT}" | grep -c '^=== ')" "0:7"
has "00: the cleanup ends it" "Cleaned up."

echo "=== The scripts say where they were copied from ==="
for s in "${UC_ROOT}"/06-lists-paging-and-fields/[0-9][0-9].*.sh; do
    case "$(basename "${s}")" in 99.*|00.*) continue ;; esac
    refs=$(sed -nE 's/^# - Copied from ((Admin|EndUser)\/API 2.0\/bash\/[^ ,;]*).*/\1/p' "${s}" | head -1 | sed 's/\.$//')
    n="$(basename "${s}")"
    if [ -z "${refs}" ]; then pass "${n}: written for this use case (no reference script)"
    elif [ -f "${REPO}/${refs}" ]; then pass "${n}: copied from ${refs}, which exists"
    else fail "${n}: its 'Copied from' file does not exist (${refs})"; fi
done

echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_06: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_06: PASS"
