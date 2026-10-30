#!/bin/bash
# ==============================================================================
# Run Admin/UseCases/08-identify-unused-objects against a stub curl, and check what each script does: the calls (method, URL, the exact query, the pages of a list), the bodies of the POSTs and the PATCH, the headers, what it prints, its exit code.
#
# The rules are tested without a server: 09 reads a map made of fixtures (the demo set as step 01 to 06 leave it), and each case changes one relation, so that an object with a reference is used, an object with none is reported, an AS2 or PeSIT site is skipped,
# a default transfer profile and a maintenance application are not judged, an enabled route is never reported, a disabled route is kept when the log names it and reported when it does not. 07 and 08 are tested on their calls: the filters, the pages (3 pages of
# 100, 100 and 50), the subscriptions of an account, the whole server, the log search by id, and the entries that are the administrator's own request. 01 to 06 on their bodies, 05 on the upload and the wait, 99 on the exact names (twice), 00 on failing
# fast and still cleaning up. Then the README: its sections, the table of rules against the rules of the script, the demo set against the list that is expected.
#
# Runs offline. Exit code 0 means clean.
# ==============================================================================
cd "$(dirname "$0")/.." || exit 1
TESTS_DIR="$(pwd)"
REPO="$(cd ../.. && pwd)"
UC_ROOT="${REPO}/Admin/UseCases"

WORK="${ST_TEST_OUTPUT:-${TESTS_DIR}/output}/bash_admin_usecase_08"
rm -rf "${WORK}"
mkdir -p "${WORK}/bin" "${WORK}/tree/API 2.0/bash" "${WORK}/tree/UseCases"

FAILED=0
pass() { printf "  PASS  %s\n" "$1"; }
fail() { printf "  FAIL  %s\n" "$1"; FAILED=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1  (expected '$3', got '$2')"; fi; }
has() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then pass "$1"; else fail "$1  (no '$2' in the output)"; fi; }
hasnt() { if printf '%s\n' "${OUT}" | grep -qF -- "$2"; then fail "$1  ('$2' is in the output)"; else pass "$1"; fi; }

cp "${TESTS_DIR}/lib/stub_curl" "${WORK}/bin/stub_curl_real" && chmod +x "${WORK}/bin/stub_curl_real"
cp "${TESTS_DIR}/lib/stub_curl_by_method" "${WORK}/bin/curl_by_method" && chmod +x "${WORK}/bin/curl_by_method"
# a wrapper in front of it: a GET whose URL holds a TEXT of STUB_FIRST_RULES ("TEXT<tab>BODY_FILE") is answered with that body the FIRST time only, so that "does it exist?" can say no and the read of the id after the POST can say yes
cat > "${WORK}/bin/curl" <<'WRAP'
#!/bin/bash
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${STUB_FIRST_RULES}" ] && [ -f "${STUB_FIRST_RULES}" ]; then
    url=""; q=""; sep="?"; prev=""; method=GET
    for a in "$@"; do
        [ "${prev}" = "--data-urlencode" ] && { q="${q}${sep}${a}"; sep="&"; }
        case "${a}" in https://*) url="${a}" ;; esac
        [ "${prev}" = "-X" ] && method="${a}"
        case "${a}" in --head|-I) method=HEAD ;; esac
        prev="${a}"
    done
    if [ "${method}" = "GET" ]; then
        while IFS=$'\t' read -r text file; do
            if [[ -n "${text}" && "${url}${q}" == *"${text}"* ]]; then
                mark="${STUB_FIRST_COUNTER}.$(printf '%s' "${text}" | cksum | cut -d' ' -f1)"
                if [ ! -e "${mark}" ]; then touch "${mark}"; export STUB_CURL_GET_BODY="${file}" STUB_CURL_GET_RULES=""; break; fi
            fi
        done < "${STUB_FIRST_RULES}"
    fi
fi
exec "${HERE}/curl_by_method" "$@"
WRAP
chmod +x "${WORK}/bin/curl"
printf '#!/bin/bash\nexit 0\n' > "${WORK}/bin/sleep" && chmod +x "${WORK}/bin/sleep"
cp "${TESTS_DIR}/fixtures/set_variables.test.sh" "${WORK}/tree/API 2.0/bash/set_variables.local.sh"
cp "${UC_ROOT}/session.sh" "${WORK}/tree/UseCases/"
cp -R "${UC_ROOT}/08-identify-unused-objects" "${WORK}/tree/UseCases/"
BASE="https://st.example.com:8444/api/v2.0"
EU="https://st.example.com:8443/api/v2.0"
UC="${WORK}/tree/UseCases/08-identify-unused-objects"
README_FILE="${UC_ROOT}/08-identify-unused-objects/README.md"
rm -rf "${UC}"/state.local.* "${UC}/session.cookie.jar"
P="example_unu_"

body() { printf '%s\n' "$2" > "${WORK}/$1.json"; echo "${WORK}/$1.json"; }
rules() {
    local out="${WORK}/rules_${RANDOM}${RANDOM}.tsv"
    : > "${out}"
    while [ "$#" -gt 1 ]; do printf '%s\t%s\n' "$1" "$2" >> "${out}"; shift 2; done
    echo "${out}"
}
list_json() {   # TOTAL JSON_OBJECT...: a list answer of Admin
    local total="$1"; shift
    jq -cn --argjson total "${total}" '{resultSet: {returnCount: ($ARGS.positional | length), totalCount: $total}, result: [$ARGS.positional[] | fromjson]}' --args "$@"
}
EMPTY="$(body empty '{"resultSet":{"returnCount":0,"totalCount":0},"result":[]}')"
reset_counters() { rm -f "${WORK}"/ctr.*; }

# run SCRIPT [PARAMS]: with a session jar in place. RULES, GET_BODY and the STATUS_* variables set the answers.
run() {
    local rel="$1"; shift
    reset_counters
    touch "${UC}/session.cookie.jar"
    OUT=$(cd "${UC}" && PATH="${WORK}/bin:${PATH}" STUB_CURL_GET_BODY="${GET_BODY:-${EMPTY}}" STUB_CURL_GET_RULES="${RULES:-}" STUB_FIRST_RULES="${FIRST:-}" STUB_FIRST_COUNTER="${WORK}/ctr.first" STUB_CURL_POST_BODY="${POST_BODY:-}" STUB_COUNTER="${WORK}/ctr" \
          STUB_CURL_STATUS="${STATUS:-200}" STUB_STATUS_GET="${STATUS_GET:-200}" STUB_STATUS_POST="${POST_STATUS:-201}" STUB_STATUS_GET_SEQ="${GET_SEQ:-}" STUB_STATUS_POST_SEQ="${POST_SEQ:-}" STUB_STATUS_HEAD="${HEAD_STATUS:-404}" \
          STUB_STATUS_DELETE="${DELETE_STATUS:-204}" STUB_STATUS_PATCH="${PATCH_STATUS:-204}" STUB_LOCATION_PREFIX="${LOCATION:-}" STUB_CURL_PRINT_CODE=1 ST_ENDUSER_PORT=8443 bash "./${rel}" "$@" 2>&1)
    RC=$?
}
calls() { printf '%s\n' "${OUT}" | awk '/^METHOD:/ {m=$2} /^URL: / {sub(/^URL: /, ""); print m " " $0}'; }
ucalls() { calls | sed 1d; }      # without the check of the session that comes first (GET /myself)
ncalls() { calls | wc -l | tr -d ' '; }
payload() { printf '%s\n' "${OUT}" | sed -n 's/^PAYLOAD_B64: //p' | sed -n "${1}p" | base64 -d; }
count_of() { ucalls | grep -c -- "$1"; }

# the map as steps 01 to 06 leave it (ids are short)
mkmap() {   # DIR PREFIX
    local d="$1"
    mkdir -p "${d}"
    printf '%s' "$2" > "${d}/prefix"
    jq -cn --arg p "${P}" '[{name: ($p + "a1")}, {name: ($p + "a2")}]' > "${d}/accounts.json"
    jq -cn --arg p "${P}" '[{id: "app1", name: ($p + "app_used"), type: "AdvancedRouting"}, {id: "app2", name: ($p + "app_unused"), type: "AdvancedRouting"}]' > "${d}/applications.json"
    jq -cn --arg p "${P}" '[{id: "c_used", name: ($p + "cert_used"), usage: "private", account: ($p + "a1")}, {id: "c_unused", name: ($p + "cert_unused"), usage: "private", account: ($p + "a1")}]' > "${d}/certificates.json"
    jq -cn --arg p "${P}" '[{id: "st1", name: ($p + "site_used"), account: ($p + "a1"), protocol: "ssh", clientCertificate: "c_used"}, {id: "st2", name: ($p + "site_step"), account: ($p + "a1"), protocol: "ssh"},
        {id: "st3", name: ($p + "site_unused"), account: ($p + "a1"), protocol: "ssh"}, {id: "st4", name: ($p + "pesit_support"), account: ($p + "a1"), protocol: "pesit"}]' > "${d}/sites.json"
    jq -cn --arg p "${P}" '[{id: "pf1", name: ($p + "profile_used"), account: ($p + "a1"), default: false}, {id: "pf2", name: ($p + "profile_unused"), account: ($p + "a1"), default: false}]' > "${d}/profiles.json"
    jq -cn --arg p "${P}" '[{id: "s_in", account: ($p + "a1"), application: ($p + "app_used"), folder: "/example_unu_in", transferConfigurations: [{site: ($p + "site_used"), transferProfile: ($p + "profile_used")}]},
        {id: "s_unused", account: ($p + "a1"), application: ($p + "app_used"), folder: "/example_unu_sub_unused", transferConfigurations: []}]' > "${d}/subscriptions.json"
    jq -cn --arg p "${P}" '
        def simple($id; $n): {id: $id, name: ($p + $n), type: "SIMPLE", steps: [{type: "Compress", status: "ENABLED"}]};
        [{id: "r_tpl_used", name: ($p + "tpl_used"), type: "TEMPLATE", steps: []}, {id: "r_tpl_unused", name: ($p + "tpl_unused"), type: "TEMPLATE", steps: []},
         simple("r_on"; "rt_on"), simple("r_old"; "rt_old"), simple("r_never"; "rt_never"),
         {id: "r_orphan", name: ($p + "rt_orphan"), type: "SIMPLE", steps: [{type: "SendToPartner", status: "ENABLED", transferSiteExpressionType: "LIST", transferSiteExpression: ($p + "site_step#!#CVD#!#")}]},
         {id: "r_comp", name: ($p + "comp_used"), type: "COMPOSITE", account: ($p + "a1"), routeTemplate: "r_tpl_used", subscriptions: ["s_in"],
          steps: [{type: "ExecuteRoute", status: "ENABLED", executeRoute: "r_on", executeRouteName: ($p + "rt_on")}, {type: "ExecuteRoute", status: "DISABLED", executeRoute: "r_old", executeRouteName: ($p + "rt_old")},
                  {type: "ExecuteRoute", status: "DISABLED", executeRoute: "r_never", executeRouteName: ($p + "rt_never")}]},
         {id: "r_comp2", name: ($p + "comp_unused"), type: "COMPOSITE", account: ($p + "a1"), routeTemplate: "r_tpl_used", subscriptions: [], steps: []}]' > "${d}/routes.json"
    printf 'r_old\t%srt_old\t1\t1\t2\nr_never\t%srt_never\t0\t0\t2\n' "${P}" "${P}" > "${d}/logsearch.tsv"
}
MAP="${UC}/state.local.map"
fresh_map() { rm -rf "${MAP}"; mkmap "${MAP}" "${P}"; }
# edit FILE JQ: change one fixture file of the map
edit() { jq -c "$2" "${MAP}/$1.json" > "${MAP}/$1.tmp" && mv "${MAP}/$1.tmp" "${MAP}/$1.json"; }
# unused_names: the names of the unused objects as 09 prints them, one for each line "Type|name"
unused() { printf '%s\n' "${OUT}" | awk '/^Total:/ {t = ""} /^  [A-Z][A-Za-z ]* \([0-9]+\)$/ {sub(/^  /, ""); sub(/ \([0-9]+\)$/, ""); t = $0; next} /^    / && t != "" {sub(/^    /, ""); sub(/  \(.*$/, ""); print t "|" $0}' | LC_ALL=C sort | tr '\n' ';'; }
EXPECTED=$(printf '%s\n' "Account|${P}a2" "Application|${P}app_unused" "Certificate|${P}cert_unused" "Composite route|${P}comp_unused" "Route|${P}rt_never" "Route|${P}rt_orphan" "Route template|${P}tpl_unused" \
    "Site|${P}site_unused" "Subscription|${P}a1 /example_unu_sub_unused" "Transfer profile|${P}profile_unused" | LC_ALL=C sort | tr '\n' ';')

echo "=== 09 the rules (no server: a map of fixtures) ==="
fresh_map
run 09.unused_objects_GET.sh
expect "09: the demo set gives exactly the ten objects, grouped by type" "${RC}:$(unused)" "0:${EXPECTED}"
has "09: the total" "Total: 10 unused objects of 9 types."
has "09: it says it is the list that was built" "This is the list that was built on purpose: 10 objects, no more and no fewer."
has "09: the route that ran in the past is kept, with the reason" "${P}rt_old  (disabled now, but the server log names it: it ran in the past)"
has "09: the one that did not is unused, with the reason" "${P}rt_never  (disabled in every step that runs it, and the server log does not name it)"
has "09: an orphan route says that no step runs it" "${P}rt_orphan  (no step of any route runs it)"
expect "09: nothing was sent to the server" "$(ncalls)" "0"
hasnt "09: the PeSIT site is not reported" "pesit_support"
hasnt "09: a used object is not reported (the site a step names)" "site_step"
for T in "Account (1)" "Application (1)" "Certificate (1)" "Composite route (1)" "Route (2)" "Route template (1)" "Site (1)" "Subscription (1)" "Transfer profile (1)"; do has "09: the heading '${T}'" "  ${T}"; done

fresh_map; edit subscriptions '. + [{id: "s3", account: "'"${P}"'a1", application: "'"${P}"'app_unused", folder: "/x", transferConfigurations: []}]'
run 09.unused_objects_GET.sh
hasnt "09: an application that a subscription uses is not unused" "${P}app_unused  ("
expect "09: and the list is not the one that was built: exit 1, and it says which object" "${RC}" "1"
has "09: (the object that was expected and is not found)" "    Application|${P}app_unused"
fresh_map; edit sites '(.[] | select(.name == "'"${P}"'site_step")) += {clientCertificate: "c_unused"}'
run 09.unused_objects_GET.sh
hasnt "09: a certificate that a site names is not unused" "${P}cert_unused  ("
fresh_map; edit subscriptions '(.[0].transferConfigurations) += [{site: "'"${P}"'site_unused", transferProfile: "'"${P}"'profile_unused"}]'
run 09.unused_objects_GET.sh
expect "09: a site and a profile named by a transfer configuration are used" "$(printf '%s\n' "${OUT}" | grep -c "site_unused  (\|profile_unused  (")" "0"
fresh_map; edit routes '(.[] | select(.name == "'"${P}"'comp_unused")) += {subscriptions: ["s_unused"]}'
run 09.unused_objects_GET.sh
expect "09: a composite route with a subscription is used, and so is the subscription it is attached to" "$(printf '%s\n' "${OUT}" | grep -c "comp_unused  (\|a1 /example_unu_sub_unused  (")" "0"
fresh_map; edit routes '(.[] | select(.name == "'"${P}"'comp_unused")) += {routeTemplate: "r_tpl_unused"}'
run 09.unused_objects_GET.sh
hasnt "09: a template that a composite route is made from is used" "tpl_unused  ("
fresh_map; edit accounts '. + [{name: "x1"}]' ; edit sites '. + [{id: "st9", name: "other_site", account: "x1", protocol: "as2"}, {id: "st10", name: "other_pesit", account: "x1", protocol: "pesit"}]'
run 09.unused_objects_GET.sh
hasnt "09: an AS2 site that nothing names is not reported" "other_site"
hasnt "09: a PeSIT site is not reported" "other_pesit"
hasnt "09: an account that owns a site is used (x1)" "x1  ("
fresh_map; edit profiles '. + [{id: "pf9", name: "TP", account: "'"${P}"'a2", default: true}]'
run 09.unused_objects_GET.sh
hasnt "09: a default transfer profile is not reported" "TP  ("
fresh_map; edit applications '. + [{id: "m1", name: "Audit Log Maintenance", type: "AuditLogMaint"}, {id: "m2", name: "FSI", type: "MBFT"}, {id: "b1", name: "BA", type: "Basic"}]'
run 09.unused_objects_GET.sh
hasnt "09: a maintenance application is not judged" "Audit Log Maintenance"
hasnt "09: (nor an MBFT one)" "FSI"
has "09: but an unused Basic application is" "BA  (no subscription uses it)"
fresh_map; edit certificates '. + [{id: "t1", name: "ca", usage: "trusted", account: null}, {id: "t2", name: "partner1", usage: "partner", account: "'"${P}"'a1"}, {id: "t3", name: null, usage: "login", account: "'"${P}"'a1"}, {id: "t4", name: "own_local", usage: "local", account: "'"${P}"'a1"}]'
run 09.unused_objects_GET.sh
hasnt "09: a trusted CA certificate (no owner) is never reported" "ca  ("
hasnt "09: a partner certificate is not judged" "partner1"
hasnt "09: a login certificate is not judged" "t3"
has "09: a local certificate with an owner is judged" "own_local  (owned by ${P}a1, and no site names it)"
fresh_map; edit sites '(.[] | select(.name == "'"${P}"'site_used")) += {clientCertificate: null, loginCertificate: "c_unused"} | (.[] | select(.name == "'"${P}"'site_used")) += {partnerCertificate: "c_used"}'
run 09.unused_objects_GET.sh
expect "09: a loginCertificate and a partnerCertificate count as references too (both certificates used)" "$(printf '%s\n' "${OUT}" | grep -c "cert_used  (\|cert_unused  (")" "0"
fresh_map; edit routes '(.[] | select(.name == "'"${P}"'comp_used") | .steps[2].status) = "ENABLED"'
run 09.unused_objects_GET.sh
hasnt "09: a route that an enabled step runs is never reported (rt_never)" "rt_never  ("
fresh_map; printf 'r_old\t%srt_old\t0\t0\t3\n' "${P}" > "${MAP}/logsearch.tsv"
run 09.unused_objects_GET.sh
has "09: a disabled route that the log does not name is reported (rt_old)" "${P}rt_old  (disabled in every step that runs it"
hasnt "09: and nothing is kept" "Kept, although disabled"
fresh_map; : > "${MAP}/logsearch.tsv"
run 09.unused_objects_GET.sh
has "09: with an empty log search, every route that only disabled steps run is reported" "${P}rt_old  (disabled in every step that runs it"
fresh_map; edit routes '(.[] | select(.name == "'"${P}"'comp_used") | .steps) += [{type: "ExecuteRoute", status: "ENABLED", executeRoute: "r_old"}]'
run 09.unused_objects_GET.sh
hasnt "09: a route that one step disables and another enables is used (rt_old)" "rt_old  ("
rm -rf "${MAP}"; mkmap "${MAP}" "other_"
run 09.unused_objects_GET.sh
expect "09: a map made for another prefix is exit 1" "${RC}" "1"
has "09: and it says to run 07 for this prefix" "There is no map for the prefix ${P}. Run 07.map_relationships_GET.sh ${P} (and 08) first."
run 09.unused_objects_GET.sh other_
expect "09: the prefix of the map is exit 0" "${RC}" "0"
hasnt "09: another prefix is not compared with the demo list" "built on purpose"
rm -rf "${MAP}"
run 09.unused_objects_GET.sh
expect "09: no map at all is exit 1" "${RC}" "1"
fresh_map; rm -f "${MAP}/logsearch.tsv"
run 09.unused_objects_GET.sh
expect "09: a map without the log search is exit 1" "${RC}" "1"
has "09: and it names step 08" "Run 08.server_log_search_GET.sh ${P} first."
for bad in "" "a b" "x/y" "-x"; do
    run 09.unused_objects_GET.sh "${bad}"
    expect "09: a PREFIX of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
done
has "09: with what a prefix is" "PREFIX is '-x': the beginning of the names to look at"
run 09.unused_objects_GET.sh a b
expect "09: two parameters is exit 2" "${RC}" "2"
has "09: with the usage" "Usage: ./09.unused_objects_GET.sh [PREFIX]"

echo "=== 07 the map and its cost ==="
rm -rf "${MAP}"
ACCS="$(body accs "$(list_json 2 '{"name":"example_unu_a1"}' '{"name":"example_unu_a2"}')")"
SUBS1="$(body subs1 "$(list_json 1 '{"id":"s1","account":"example_unu_a1","folder":"/f"}')")"
SUBS2="$(body subs2 "$(list_json 1 '{"id":"s2","account":"example_unu_a2","folder":"/g"}')")"
ONE="$(body one "$(list_json 1 '{"id":"x1","name":"example_unu_x"}')")"
ROUTES="$(body routes "$(list_json 3 '{"id":"r1","name":"example_unu_t","type":"TEMPLATE"}' '{"id":"r2","name":"example_unu_s","type":"SIMPLE"}' '{"id":"r3","name":"example_unu_c","type":"COMPOSITE"}')")"
RULES="$(rules 'accounts?name=' "${ACCS}" 'subscriptions?account=example_unu_a1' "${SUBS1}" 'subscriptions?account=example_unu_a2' "${SUBS2}" 'routes?name=' "${ROUTES}")" GET_BODY="${ONE}" run 07.map_relationships_GET.sh
expect "07: the lists are filtered by the prefix (name=example_unu_*), with fields where they help, in pages of 100, then the subscriptions of each account" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/accounts?name=example_unu_*&fields=name&limit=100&offset=0 GET ${BASE}/applications?name=example_unu_*&fields=id,name&limit=100&offset=0 GET ${BASE}/certificates?name=example_unu_*&fields=id,name,usage,account&limit=100&offset=0 GET ${BASE}/sites?name=example_unu_*&fields=id,name,account,protocol,clientCertificate,loginCertificate,partnerCertificate&limit=100&offset=0 GET ${BASE}/transferProfiles?name=example_unu_*&fields=id,name,account,default&limit=100&offset=0 GET ${BASE}/routes?name=example_unu_*&limit=100&offset=0 GET ${BASE}/subscriptions?account=example_unu_a1&fields=id,account,application,folder,transferConfigurations&limit=100 GET ${BASE}/subscriptions?account=example_unu_a2&fields=id,account,application,folder,transferConfigurations&limit=100 "
has "07: the cost table has a head" "What was read"
has "07: the routes are read in one call" "routes                                         1         3"
has "07: the subscriptions cost one call for each account" "subscriptions (one call for each account)      2         2"
has "07: with a total of 8 calls and 11 objects" "Total                                          8        11"
has "07: counts what it read" "2 accounts, 1 applications, 1 certificates, 1 sites, 1 transfer profiles, 3 routes (1 templates, 1 composite, 1 simple), 2 subscriptions."
expect "07: it keeps the map and the prefix in state.local.map" "$(cat "${MAP}/prefix"):$(jq length "${MAP}/routes.json"):$(jq length "${MAP}/subscriptions.json")" "${P}:3:2"
# paging: 250 certificates in pages of 100
page() { jq -cn --argjson n "$1" --argjson total 250 '{resultSet: {returnCount: $n, totalCount: $total}, result: [range($n) | {id: "c\(.)", name: "n\(.)", usage: "trusted", account: null}]}'; }
RULES="$(rules 'certificates?name=example_unu_*&fields=id,name,usage,account&limit=100&offset=0' "$(body p0 "$(page 100)")" 'certificates?name=example_unu_*&fields=id,name,usage,account&limit=100&offset=100' "$(body p1 "$(page 100)")" \
        'certificates?name=example_unu_*&fields=id,name,usage,account&limit=100&offset=200' "$(body p2 "$(page 50)")" 'accounts?name=' "${EMPTY}")" run 07.map_relationships_GET.sh
expect "07: a list of 250 is read in three calls, with offsets 0, 100 and 200" "$(ucalls | grep -c 'certificates?')" "3"
expect "07: (the offsets)" "$(ucalls | grep 'certificates?' | sed -E 's/.*offset=//' | tr '\n' ' ')" "0 100 200 "
has "07: and the cost line says 3 calls and 250 objects" "certificates                                   3       250"
expect "07: all 250 are kept" "$(jq length "${MAP}/certificates.json")" "250"
RULES="$(rules 'accounts?name=' "${EMPTY}")" run 07.map_relationships_GET.sh other_
expect "07: another prefix filters by that prefix" "$(ucalls | head -1)" "GET ${BASE}/accounts?name=other_*&fields=name&limit=100&offset=0"
expect "07: an account-less prefix has no per-account subscription call" "$(count_of 'subscriptions')" "0"
GET_SEQ="200 403" GET_BODY="$(body forbidden '{"message":"Error validating request","validationErrors":["Access denied"]}')" run 07.map_relationships_GET.sh
expect "07: a refused list is exit 1, after the session check and that one call" "${RC}:$(ucalls | wc -l | tr -d ' ')" "1:1"
has "07: with the code and the reason" "HTTP 403: Access denied"
GET_BODY="$(body nototal '{"message":"surprise"}')" run 07.map_relationships_GET.sh
expect "07: an answer that is no list is exit 1" "${RC}" "1"
has "07: and it says why" "the answer has no result and no resultSet.totalCount, so there is nothing to read."
run 07.map_relationships_GET.sh "a b"
expect "07: a bad prefix is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
run 07.map_relationships_GET.sh a b
expect "07: two parameters is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 08 the log search ==="
fresh_map
LOG_FOUND="$(body logfound "$(list_json 3 '{"time":"Fri, 30 Oct 2026 11:27:05 +0200","message":"AR0011: [a1] [example_unu_comp_used]  Sandbox environment {/home/a1/.stfs/objects/8a/x/r_old} used for route execution"}' '{"message":"GET request for the following resource: /api/v2.0/logs/server?message=r_old&limit=100, has been initiated by the administrator with name: admin"}' '{"message":"Result from GET request for the following resource: /api/v2.0/logs/server?message=r_old&limit=100, made by the administrator - OK."}')")"
LOG_SELF="$(body logself "$(list_json 2 '{"message":"GET request for the following resource: /api/v2.0/logs/server?message=r_never&limit=100, has been initiated by the administrator"}' '{"message":"Result from GET request for the following resource: /api/v2.0/logs/server?message=r_never&limit=100 - OK."}')")"
rm -f "${MAP}/logsearch.tsv"
RULES="$(rules 'message=r_old' "${LOG_FOUND}" 'message=r_never' "${LOG_SELF}")" run 08.server_log_search_GET.sh
expect "08: one call for each route that only disabled steps run (r_old and r_never), by id, 100 entries at most; r_on, run by an enabled step, is not searched" "${RC}:$(ucalls | tr '\n' ' ')" \
  "0:GET ${BASE}/logs/server?message=r_never&limit=100 GET ${BASE}/logs/server?message=r_old&limit=100 "
has "08: a route named by an entry that is not a request is found" "${P}rt_old: found, 1 entries that name it (the first: AR0011: [a1] [example_unu_comp_used]  Sandbox environment"
has "08: a route named only by the administrator's own requests is not found" "${P}rt_never: not found (2 entries were only the administrator's own requests for this search)"
has "08: it counts the calls" "2 call(s) to the server log"
expect "08: it writes the result: id, name, found, entries, entries ignored" "$(cat "${MAP}/logsearch.tsv" | tr '\t\n' ',;')" "r_never,${P}rt_never,0,0,2;r_old,${P}rt_old,1,1,2;"
RULES="$(rules 'message=' "${EMPTY}")" run 08.server_log_search_GET.sh
expect "08: an empty log is 'not found' for both" "$(awk -F'\t' '{print $3}' "${MAP}/logsearch.tsv" | tr '\n' ' ')" "0 0 "
edit routes '(.[] | select(.name == "'"${P}"'comp_used") | .steps[1].status) = "ENABLED"'
RULES="$(rules 'message=' "${EMPTY}")" run 08.server_log_search_GET.sh
expect "08: a route that an enabled step runs is not searched (only r_never is)" "$(ucalls | tr '\n' ' ')" "GET ${BASE}/logs/server?message=r_never&limit=100 "
edit routes '(.[] | select(.name == "'"${P}"'comp_used") | .steps) |= map(select(.executeRoute == "r_on"))'
RULES="$(rules 'message=' "${EMPTY}")" run 08.server_log_search_GET.sh
has "08: when nothing needs a search it says so" "There is none: every route that a step runs is run by an enabled step, or no step runs it."
expect "08: and makes no call to the log" "$(count_of 'logs/server')" "0"
fresh_map; rm -f "${MAP}/logsearch.tsv"
GET_SEQ="200 403" GET_BODY="$(body forbidden2 '{"message":"Error validating request","validationErrors":["Access denied"]}')" run 08.server_log_search_GET.sh
expect "08: a refused search is exit 1" "${RC}" "1"
has "08: with the route, the code and the reason" "The server log, for ${P}rt_never: HTTP 403: Access denied"
rm -rf "${MAP}"
run 08.server_log_search_GET.sh
expect "08: no map is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
has "08: and it names step 07" "Run 07.map_relationships_GET.sh ${P} first."
run 08.server_log_search_GET.sh "x y"
expect "08: a bad prefix is exit 2" "${RC}" "2"

echo "=== 10 the whole server ==="
RULES="$(rules 'accounts?' "${ACCS}" 'routes?' "${ROUTES}")" GET_BODY="${ONE}" run 10.whole_server_GET.sh
expect "10: no name filter; the subscriptions in one list; each list in pages of 100" "$(ucalls | head -7 | tr '\n' ' ')" \
  "GET ${BASE}/accounts?fields=name&limit=100&offset=0 GET ${BASE}/applications?fields=id,name&limit=100&offset=0 GET ${BASE}/certificates?fields=id,name,usage,account&limit=100&offset=0 GET ${BASE}/sites?fields=id,name,account,protocol,clientCertificate,loginCertificate,partnerCertificate&limit=100&offset=0 GET ${BASE}/transferProfiles?fields=id,name,account,default&limit=100&offset=0 GET ${BASE}/routes?limit=100&offset=0 GET ${BASE}/subscriptions?fields=id,account,application,folder,transferConfigurations&limit=100&offset=0 "
has "10: it says it is read only" "This is read only: it changes and deletes nothing."
expect "10: it only reads: GET calls and no other method" "$(printf '%s\n' "${OUT}" | grep '^METHOD:' | sort -u | tr '\n' ' ')" "METHOD: GET "
has "10: the cost, then the unused objects, then how long it took" "Unused objects"
has "10: the total of the time" "The whole server took"
expect "10: it keeps its map apart from the one of the demo set" "$([ -f "${UC}/state.local.mapall/routes.json" ] && echo yes):$(cat "${UC}/state.local.mapall/prefix")" "yes:"
run 10.whole_server_GET.sh now
expect "10: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 01 the accounts and the certificates ==="
LOCATION=Loc POST_BODY="" run 01.accounts_certificates_POST.sh
POSTS=$(calls | grep -c '^POST')
expect "01: the accounts (2) then the two certificates (multipart); HEAD of each account first" "${RC}:$(ucalls | awk '{print $1 " " $2}' | sed -E "s#${BASE}/##" | tr '\n' ',')" \
  "0:HEAD accounts/${P}a1,HEAD accounts/${P}a2,POST accounts,POST accounts,GET certificates?name=${P}cert_used&fields=id,name,POST certificates,GET certificates?name=${P}cert_used&fields=id,name,GET certificates?name=${P}cert_unused&fields=id,name,POST certificates,GET certificates?name=${P}cert_unused&fields=id,name,"
expect "01: the first account body: name, type user, home folder, the fixed uid and gid, the password" "$(payload 1 | jq -c '[.name, .type, .homeFolder, .uid, .gid, (.user.passwordCredentials.password | length > 8)]')" "[\"${P}a1\",\"user\",\"/home/${P}a1\",\"58201\",\"58201\",true]"
expect "01: the second account has the next user id" "$(payload 2 | jq -c '[.name, .uid, .gid]')" "[\"${P}a2\",\"58202\",\"58202\"]"
expect "01: both accounts have the same password, kept in the password file" "$([ "$(payload 1 | jq -r .user.passwordCredentials.password)" = "$(cat "${UC}/state.local.password")" ] && [ "$(payload 2 | jq -r .user.passwordCredentials.password)" = "$(cat "${UC}/state.local.password")" ] && echo same)" "same"
expect "01: the password file is not readable by others" "$(ls -l "${UC}/state.local.password" | cut -c1-10)" "-rw-------"
expect "01: the certificates are posted as multipart/mixed" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: multipart/mixed; boundary=BOUNDARY')" "2"
expect "01: all the writes carry the Referer (the stub refuses one without)" "${RC}:$(printf '%s\n' "${OUT}" | grep -c 'STUB_ERROR')" "0:0"
HEAD_STATUS=200 run 01.accounts_certificates_POST.sh
expect "01: an account that exists is exit 1, and nothing is made" "${RC}:$(calls | grep -c '^POST')" "1:0"
has "01: and it says which and how to remove it" "${P}a1 exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."
HEAD_STATUS=500 run 01.accounts_certificates_POST.sh
expect "01: a HEAD that is neither 200 nor 404 is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
GET_BODY="$(body hascert "$(list_json 1 '{"id":"c1","name":"example_unu_cert_used"}')")" run 01.accounts_certificates_POST.sh
expect "01: a certificate that exists is exit 1 (after the accounts)" "${RC}" "1"
has "01: and it says which" "The certificate ${P}cert_used exists already."
POST_SEQ="201 400" run 01.accounts_certificates_POST.sh
expect "01: a refused account is exit 1, after the first" "${RC}:$(calls | grep -c '^POST')" "1:2"
run 01.accounts_certificates_POST.sh now
expect "01: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"

echo "=== 02 the sites and the profiles ==="
rm -rf "${UC}"/state.local.*
CERT_BODY="$(body cert1 "$(list_json 1 '{"id":"c_used","name":"example_unu_cert_used"}')")"
RULES="$(rules 'certificates?name=' "${CERT_BODY}")" LOCATION=Loc run 02.partnerships_POST.sh
expect "02: the certificate is looked up by name, the sites and the profiles checked, then 4 sites and 2 profiles posted" "${RC}:$(ucalls | grep -c '^POST'):$(ucalls | grep '^POST' | sed -E "s#.*${BASE}/##" | tr '\n' ' ')" "0:6:sites sites sites sites transferProfiles transferProfiles "
expect "02: the site that uses the certificate names it by id" "$(payload 1 | jq -c '[.name, .type, .account, .clientCertificate, .host, .port]')" "[\"${P}site_used\",\"ssh\",\"${P}a1\",\"c_used\",\"partner.example.com\",\"22\"]"
expect "02: the other two have no certificate" "$(payload 2 | jq -r 'has("clientCertificate")'):$(payload 3 | jq -r 'has("clientCertificate")')" "false:false"
expect "02: the PeSIT site is made before the profiles" "$(payload 4 | jq -c '[.name, .type, .protocol, .port]')" "[\"${P}pesit_support\",\"pesit\",\"pesit\",\"17617\"]"
expect "02: a profile has a name, the account, a mapping and a label option" "$(payload 5 | jq -c '[.name, .account, .sendMapping, .fileLabelOption]')" "[\"${P}profile_used\",\"${P}a1\",\"/*\",\"DONT_SEND\"]"
GET_BODY="${EMPTY}" run 02.partnerships_POST.sh
expect "02: without the certificate of step 01 it is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
has "02: and it names step 01" "The certificate ${P}cert_used is not on the server. Run 01.accounts_certificates_POST.sh first."
RULES="$(rules 'certificates?name=' "${CERT_BODY}" 'sites?name=' "$(body site_exists "$(list_json 1 '{"id":"st1","name":"example_unu_site_used"}')")")" run 02.partnerships_POST.sh
expect "02: a site that exists is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
POST_SEQ="201 400" RULES="$(rules 'certificates?name=' "${CERT_BODY}")" run 02.partnerships_POST.sh
expect "02: a refused site is exit 1, after the first" "${RC}:$(calls | grep -c '^POST')" "1:2"
run 02.partnerships_POST.sh now
expect "02: a parameter is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 03 the applications and the subscriptions ==="
SITE_BODY="$(body site1 "$(list_json 1 '{"id":"st1","name":"example_unu_site_used"}')")"
RULES="$(rules 'sites?name=' "${SITE_BODY}" 'subscriptions?account=' "${EMPTY}")" LOCATION=Loc run 03.subscriptions_POST.sh
expect "03: two applications, then the two subscriptions" "${RC}:$(ucalls | grep '^POST' | sed -E "s#.*${BASE}/##" | tr '\n' ' ')" "0:applications applications subscriptions subscriptions "
expect "03: an application is of type AdvancedRouting" "$(payload 1 | jq -c '[.type, .name]')" "[\"AdvancedRouting\",\"${P}app_used\"]"
expect "03: the first subscription has its site and its profile, by name, in the transfer configuration" "$(payload 3 | jq -c '[.account, .application, .folder, .transferConfigurations[0].site, .transferConfigurations[0].transferProfile, .transferConfigurations[0].outbound]')" \
  "[\"${P}a1\",\"${P}app_used\",\"/example_unu_in\",\"${P}site_used\",\"${P}profile_used\",false]"
expect "03: the second has nothing attached" "$(payload 4 | jq -c '[.folder, has("transferConfigurations")]')" "[\"/example_unu_sub_unused\",false]"
RULES="$(rules 'sites?name=' "${EMPTY}")" run 03.subscriptions_POST.sh
expect "03: without the site of step 02 it is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
RULES="$(rules 'sites?name=' "${SITE_BODY}" 'subscriptions?account=' "$(body has_sub "$(list_json 1 '{"id":"s1","folder":"/x"}')")")" run 03.subscriptions_POST.sh
expect "03: an account that has subscriptions already is exit 1" "${RC}:$(calls | grep -c '^POST')" "1:0"
has "03: and it says so" "${P}a1 has subscriptions already."
RULES="$(rules 'sites?name=' "${SITE_BODY}" 'subscriptions?account=' "${EMPTY}")" POST_SEQ="201 201 400" run 03.subscriptions_POST.sh
expect "03: a refused subscription is exit 1" "${RC}" "1"
run 03.subscriptions_POST.sh now
expect "03: a parameter is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 04 the routes ==="
SUB_BODY="$(body subA "$(list_json 1 '{"id":"s_in","folder":"/example_unu_in"}')")"
SITE_STEP_BODY="$(body site_step "$(list_json 1 '{"id":"st2","name":"example_unu_site_step"}')")"
RT_BODY() { body "rt_$1" "$(list_json 1 "$(jq -cn --arg i "id_$1" --arg n "${P}$1" '{id: $i, name: $n}')")"; }
ROUTE_RULES() { rules 'subscriptions?account=' "${SUB_BODY}" 'sites?name=' "${SITE_STEP_BODY}" "routes?name=${P}tpl_used&fields=id,name" "$(RT_BODY tpl_used)" "routes?name=${P}rt_on&fields=id,name" "$(RT_BODY rt_on)" \
          "routes?name=${P}rt_old&fields=id,name" "$(RT_BODY rt_old)" "routes?name=${P}rt_never&fields=id,name" "$(RT_BODY rt_never)" "routes?name=" "${EMPTY}"; }
NOT_THERE() { rules "routes?name=${P}tpl_used&fields=id,name" "${EMPTY}" "routes?name=${P}tpl_unused&fields=id,name" "${EMPTY}" "routes?name=${P}rt_on&fields=id,name" "${EMPTY}" "routes?name=${P}rt_old&fields=id,name" "${EMPTY}" \
          "routes?name=${P}rt_never&fields=id,name" "${EMPTY}" "routes?name=${P}rt_orphan&fields=id,name" "${EMPTY}" "routes?name=${P}comp_used&fields=id,name" "${EMPTY}" "routes?name=${P}comp_unused&fields=id,name" "${EMPTY}"; }
RULES="$(ROUTE_RULES)" FIRST="$(NOT_THERE)" LOCATION=Loc run 04.routes_POST.sh
expect "04: two templates, four simple routes, two composite routes are posted to /routes" "${RC}:$(ucalls | grep -c '^POST .*/routes$')" "0:8"
expect "04: a template" "$(payload 1 | jq -c '[.name, .type, .conditionType]')" "[\"${P}tpl_used\",\"TEMPLATE\",\"MATCH_ALL\"]"
expect "04: a simple route has a Compress step that makes its own archive" "$(payload 3 | jq -c '[.name, .type, .steps[0].type, .steps[0].singleArchiveName, .steps[0].status]')" "[\"${P}rt_on\",\"SIMPLE\",\"Compress\",\"${P}rt_on.zip\",\"ENABLED\"]"
expect "04: the orphan has a SendToPartner step to the site, in the form SITE#!#CVD#!#" "$(payload 6 | jq -c '[.name, .steps[0].type, .steps[0].transferSiteExpression, .steps[0].transferSiteExpressionType]')" "[\"${P}rt_orphan\",\"SendToPartner\",\"${P}site_step#!#CVD#!#\",\"LIST\"]"
expect "04: the composite route has the template, the account, the subscription and three steps: enabled, enabled, disabled" "$(payload 7 | jq -c '[.name, .type, .account, .routeTemplate, .subscriptions, [.steps[] | .status], [.steps[] | .executeRoute]]')" \
  "[\"${P}comp_used\",\"COMPOSITE\",\"${P}a1\",\"id_tpl_used\",[\"s_in\"],[\"ENABLED\",\"ENABLED\",\"DISABLED\"],[\"id_rt_on\",\"id_rt_old\",\"id_rt_never\"]]"
expect "04: the unused composite route has no step and no subscription" "$(payload 8 | jq -c '[.name, has("steps"), has("subscriptions"), .routeTemplate]')" "[\"${P}comp_unused\",false,false,\"id_tpl_used\"]"
RULES="$(rules 'subscriptions?account=' "${EMPTY}")" run 04.routes_POST.sh
expect "04: without the subscription of step 03 it is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
RULES="$(rules 'subscriptions?account=' "${SUB_BODY}" 'sites?name=' "${EMPTY}")" run 04.routes_POST.sh
expect "04: without the site of step 02 it is exit 1" "${RC}:$(calls | grep -c '^POST')" "1:0"
RULES="$(rules 'subscriptions?account=' "${SUB_BODY}" 'sites?name=' "${SITE_STEP_BODY}" "routes?name=${P}tpl_used&fields=id,name" "$(RT_BODY tpl_used)" 'routes?name=' "${EMPTY}")" run 04.routes_POST.sh
expect "04: a route that exists is exit 1, nothing made" "${RC}:$(calls | grep -c '^POST')" "1:0"
RULES="$(ROUTE_RULES)" FIRST="$(NOT_THERE)" POST_SEQ="201 201 400" run 04.routes_POST.sh
expect "04: a refused route stops the script, exit 1, after the third POST" "${RC}:$(calls | grep -c '^POST')" "1:3"
run 04.routes_POST.sh now
expect "04: a parameter is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 05 the upload and the log ==="
printf 'Ex1!password' > "${UC}/state.local.password"
IDS_RULES() { rules "routes?name=${P}rt_on&fields=id,name" "$(RT_BODY rt_on)" "routes?name=${P}rt_old&fields=id,name" "$(RT_BODY rt_old)" "routes?name=${P}rt_never&fields=id,name" "$(RT_BODY rt_never)" \
              'message=id_rt_on' "$(body l_on "$(list_json 1 '{"time":"Fri, 30 Oct 2026 11:27:05 +0200","message":"AR0011: [a1] [example_unu_comp_used]  Sandbox environment {/x/id_rt_on} used for route execution"}')")" \
              'message=id_rt_old' "$(body l_old "$(list_json 2 '{"time":"Fri, 30 Oct 2026 11:27:06 +0200","message":"AR0011: [a1] [example_unu_comp_used]  Sandbox environment {/x/id_rt_old} used for route execution"}' '{"message":"GET request for the following resource: /api/v2.0/logs/server?message=id_rt_old"}')")" \
              'message=id_rt_never' "${LOG_SELF}"; }
RULES="$(IDS_RULES)" POST_BODY="$(body op '{"id":"op-1"}')" run 05.upload_POST.sh 5
expect "05: the upload is declared with POST /fileOperations on the End User port, then the content is PUT to the operation" "${RC}:$(ucalls | grep -E '^(POST|PUT)' | sed -E "s#${EU}/##" | tr '\n' ' ')" "0:POST fileOperations PUT fileOperations/op-1 "
expect "05: as the account, with its password (Basic authentication)" "$(printf '%s\n' "${OUT}" | grep '^BASIC_AUTH:' | sort -u | tr '\n' ' ')" "BASIC_AUTH: ${P}a1:Ex1!password "
expect "05: the file goes to the folder of the subscription, as BINARY" "$(payload 1 | jq -c '[.operation, (.filePath | sub("hello_[0-9]+"; "hello_N")), .customAttributes.transferMode]')" "[\"Upload\",\"/example_unu_in/hello_N.txt\",\"BINARY\"]"
expect "05: the content is sent as application/octet-stream" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: application/octet-stream')" "1"
expect "05: the log is searched by the id of each route that ran" "$(ucalls | grep -c 'logs/server?message=id_rt_on&limit=100'):$(ucalls | grep -c 'logs/server?message=id_rt_old&limit=100')" "$(ucalls | grep -c 'logs/server?message=id_rt_on&limit=100'):$(ucalls | grep -c 'logs/server?message=id_rt_old&limit=100')"
has "05: the entry of the enabled route is shown" "${P}rt_on (id id_rt_on): 1 entries that name it"
has "05: the entry of the route that ran and is disabled later is shown, and the administrator's own request is told apart" "${P}rt_old (id id_rt_old): 1 entries that name it"
has "05: (the request that is not counted)" "(and 1 entries that are only the administrator's own requests for this search)"
has "05: the route of the disabled step has no entry" "${P}rt_never (id id_rt_never): 0 entries that name it"
has "05: and the script says the log does not tell a skipped route" "the log does not say that a route was skipped."
RULES="$(IDS_RULES)" POST_BODY="$(body op2 '{}')" run 05.upload_POST.sh 5
expect "05: no operation id is exit 1, and the content is not sent" "${RC}:$(calls | grep -c '^PUT')" "1:0"
has "05: with what happened" "no operation id came back, so nothing was uploaded."
RULES="$(rules "routes?name=${P}rt_on&fields=id,name" "$(RT_BODY rt_on)" "routes?name=${P}rt_old&fields=id,name" "$(RT_BODY rt_old)" "routes?name=${P}rt_never&fields=id,name" "$(RT_BODY rt_never)" 'message=' "${LOG_SELF}")" \
    POST_BODY="$(body op3 '{"id":"op-1"}')" run 05.upload_POST.sh 1
expect "05: a log that never names the routes is exit 1 after the wait" "${RC}" "1"
has "05: and it says what to look at" "After 1 s the server log names"
RULES="$(IDS_RULES)" POST_BODY="$(body op4 '{"id":"op-1"}')" STATUS_PUT=500 run 05.upload_POST.sh 5
rm -f "${UC}/state.local.password"
run 05.upload_POST.sh
expect "05: no password file is exit 1, nothing sent" "${RC}:$(ncalls)" "1:0"
has "05: and it names step 01" "run 01.accounts_certificates_POST.sh first."
printf 'x' > "${UC}/state.local.password"
for bad in 0 x -1; do run 05.upload_POST.sh "${bad}"; expect "05: SECONDS of '${bad}' is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"; done
run 05.upload_POST.sh 5 6
expect "05: two parameters is exit 2" "${RC}" "2"
rm -f "${UC}/state.local.password"

echo "=== 06 the step is disabled ==="
COMP_ON="$(jq -cn '{id: "r_comp", name: "example_unu_comp_used", steps: [{status: "ENABLED", executeRoute: "id_rt_on", executeRouteName: "example_unu_rt_on"}, {status: "ENABLED", executeRoute: "id_rt_old", executeRouteName: "example_unu_rt_old"}, {status: "DISABLED", executeRoute: "id_rt_never", executeRouteName: "example_unu_rt_never"}]}')"
COMP_OFF="$(printf '%s' "${COMP_ON}" | jq -c '.steps[1].status = "DISABLED"')"
SEQ_DIR="${WORK}/seq06"; mkdir -p "${SEQ_DIR}"
printf '%s' "${COMP_ON}" > "${SEQ_DIR}/1.json"
run_seq() { local rel="$1"; shift; rm -f "${SEQ_DIR}/.served"; STUB_CURL_GET_SEQUENCE="${SEQ_DIR}" run "${rel}" "$@"; }
# the session check (GET /myself) is not answered from the sequence: the jar is there, so it is the first GET and takes the first file; the files are therefore: myself, lookup of the composite, lookup of rt_old, route, route after
printf '%s' '{}' > "${SEQ_DIR}/1.json"
printf '%s' "$(list_json 1 '{"id":"r_comp","name":"example_unu_comp_used"}')" > "${SEQ_DIR}/2.json"
printf '%s' "$(list_json 1 '{"id":"id_rt_old","name":"example_unu_rt_old"}')" > "${SEQ_DIR}/3.json"
printf '%s' "${COMP_ON}" > "${SEQ_DIR}/4.json"
printf '%s' "${COMP_OFF}" > "${SEQ_DIR}/5.json"
printf '%s' "${COMP_OFF}" > "${SEQ_DIR}/6.json"
run_seq 06.step_PATCH_disable.sh
expect "06: the route is read, the position of the step is found, the step is patched, and the route is read again" "${RC}:$(ucalls | sed -E "s#${BASE}/##" | tr '\n' ',')" \
  "0:GET routes?name=example_unu_comp_used&fields=id,name,GET routes?name=example_unu_rt_old&fields=id,name,GET routes/r_comp,PATCH routes/r_comp,GET routes/r_comp,"
expect "06: the PATCH is replace /steps/1/status, DISABLED (the position of rt_old, from 0)" "$(payload 1)" '[{"op":"replace","path":"/steps/1/status","value":"DISABLED"}]'
expect "06: it sends Content-Type and the csrfToken" "$(printf '%s\n' "${OUT}" | grep -c '^HEADER: Content-Type: application/json'):$(printf '%s\n' "${OUT}" | grep -c '^HEADER: csrfToken: ')" "1:1"
has "06: it prints the steps before" "  step 1: ENABLED  runs example_unu_rt_old"
has "06: and after" "  step 1: DISABLED  runs example_unu_rt_old"
has "06: and says the log still names it" "example_unu_rt_old is disabled now, and the server log still names it (step 05)."
PATCH_STATUS=400 run_seq 06.step_PATCH_disable.sh
expect "06: a refused PATCH is exit 1" "${RC}" "1"
has "06: with the status and the path" "PATCH /routes/r_comp (replace /steps/1/status): HTTP 400. The step was not changed."
printf '%s' "${COMP_ON}" > "${SEQ_DIR}/5.json"
run_seq 06.step_PATCH_disable.sh
expect "06: a step that is still enabled after the PATCH is exit 1" "${RC}" "1"
has "06: and it says so" "The step that runs example_unu_rt_old is ENABLED, not DISABLED."
printf '%s' "$(printf '%s' "${COMP_ON}" | jq -c '.steps |= map(select(.executeRoute != "id_rt_old"))')" > "${SEQ_DIR}/4.json"
run_seq 06.step_PATCH_disable.sh
expect "06: a composite route with no step that runs rt_old is exit 1, nothing patched" "${RC}:$(calls | grep -c '^PATCH')" "1:0"
rm -rf "${SEQ_DIR}"
run 06.step_PATCH_disable.sh
expect "06: without the composite route it is exit 1, nothing patched" "${RC}:$(calls | grep -c '^PATCH')" "1:0"
has "06: and it names step 04" "Run 04.routes_POST.sh first."
run 06.step_PATCH_disable.sh now
expect "06: a parameter is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 99 the cleanup ==="
ALL_RULES() { rules "routes?name=${P}comp_used" "$(RT_BODY comp_used)" "routes?name=${P}comp_unused" "$(RT_BODY comp_unused)" "routes?name=${P}rt_orphan" "$(RT_BODY rt_orphan)" "routes?name=${P}tpl_used" "$(RT_BODY tpl_used)" \
              "routes?name=${P}tpl_unused" "$(RT_BODY tpl_unused)" 'applications?name=' "$(body app "$(list_json 1 '{"id":"a1","name":"example_unu_app_used"}')")" 'transferProfiles?name=' "$(body prf "$(list_json 1 '{"id":"p1","name":"example_unu_profile_used"}')")" \
              'sites?name=' "$(body sit "$(list_json 1 '{"id":"t1","name":"example_unu_site_used"}')")" 'accounts?name=' "$(body acc "$(list_json 1 '{"id":"x1","name":"example_unu_a1"}')")" \
              'subscriptions?account=' "$(body sbs "$(list_json 3 '{"id":"sA","folder":"/example_unu_in"}' '{"id":"sB","folder":"/example_unu_sub_unused"}' '{"id":"sC","folder":"/somebody_elses"}')")"; }
mkdir -p "${UC}/state.local.map" "${UC}/state.local.mapall"; printf 'x' > "${UC}/state.local.password"
RULES="$(ALL_RULES)" run 99.cleanup_DELETE.sh
DELETES=$(ucalls | grep '^DELETE' | sed -E "s#${BASE}/##" | tr '\n' ' ')
expect "99: it deletes by id (routes, subscriptions, profiles, sites), and by name (applications, accounts), and ends the session" "${RC}:${DELETES}" \
  "0:DELETE routes/id_comp_used DELETE routes/id_comp_unused DELETE subscriptions/sA DELETE subscriptions/sB DELETE routes/id_rt_orphan DELETE routes/id_tpl_used DELETE routes/id_tpl_unused DELETE applications/example_unu_app_used DELETE transferProfiles/p1 DELETE sites/t1 DELETE accounts/example_unu_a1 DELETE myself "
expect "99: a subscription of the account that is not of this use case is not deleted (sC)" "$(printf '%s\n' "${DELETES}" | grep -c sC)" "0"
expect "99: the state is removed" "$([ -e "${UC}/state.local.map" ] || [ -e "${UC}/state.local.mapall" ] || [ -e "${UC}/state.local.password" ] && echo left || echo gone)" "gone"
has "99: it says what it deleted" "${P}a1 was deleted."
has "99: and what was not there" "${P}a2 is not there."
RULES="$(rules 'accounts?name=' "${EMPTY}")" GET_BODY="${EMPTY}" run 99.cleanup_DELETE.sh
expect "99: run again, with nothing there, it deletes nothing and is exit 0" "${RC}:$(ucalls | grep -c '^DELETE .*/myself' ):$(ucalls | grep '^DELETE' | grep -vc myself)" "0:1:0"
has "99: and says so" "${P}rt_on is not there."
DELETE_STATUS=500 RULES="$(ALL_RULES)" run 99.cleanup_DELETE.sh
expect "99: a delete that is refused is exit 1, and the others are still tried" "${RC}:$(ucalls | grep -c '^DELETE')" "1:12"
has "99: with the name" "${P}comp_used could not be deleted (HTTP 500): delete it by hand."
DELETE_STATUS=404 RULES="$(ALL_RULES)" run 99.cleanup_DELETE.sh
expect "99: a 404 is not an error" "${RC}" "0"
run 99.cleanup_DELETE.sh now
expect "99: a parameter is exit 2" "${RC}:$(ncalls)" "2:0"

echo "=== 00 run_all ==="
run 00.run_all.sh now
expect "00: a parameter is exit 2, nothing sent" "${RC}:$(ncalls)" "2:0"
HEAD_STATUS=200 run 00.run_all.sh
expect "00: when step 01 fails it stops, says which, and the cleanup still runs" "${RC}" "1"
has "00: (the step)" "=== 01.accounts_certificates_POST ==="
has "00: (it says so)" "01.accounts_certificates_POST failed."
hasnt "00: (step 02 is not run)" "=== 02.partnerships_POST ==="
has "00: (the cleanup runs)" "=== 99.cleanup_DELETE ==="
has "00: (and it deleted the session)" "The administrator's session was ended"

echo "=== the files and the README ==="
for f in 00.run_all 01.accounts_certificates_POST 02.partnerships_POST 03.subscriptions_POST 04.routes_POST 05.upload_POST 06.step_PATCH_disable 07.map_relationships_GET 08.server_log_search_GET 09.unused_objects_GET 10.whole_server_GET 99.cleanup_DELETE; do
    [ -x "${UC_ROOT}/08-identify-unused-objects/${f}.sh" ] && pass "${f}.sh is there and executable" || fail "${f}.sh is missing or not executable"
done
python3 - "${README_FILE}" "${UC_ROOT}/08-identify-unused-objects/lib.sh" "${UC_ROOT}/08-identify-unused-objects/unused.jq" <<'PY' && pass "README: the sections, the rules table against unused.jq, the demo set against the expected list, the claims of the experiment" || fail "README: a section, a rule or a claim is missing"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
lib = open(sys.argv[2], encoding="utf-8").read()
jq = open(sys.argv[3], encoding="utf-8").read()
for heading in ("## The relationships", "## The rules", "## The demo set", "## The steps", "## What the log says about a route (the experiment of step 05)", "## The cost of the map", "## Reading the output", "## What is not covered", "## What to check before you delete"):
    assert heading in text, heading
# every type of the rules table is a type that lib and unused.jq know
types = re.findall(r'UC_TYPES=\((.*?)\)', lib, re.S)[0]
for t in re.findall(r'"([^"]+)"', types):
    assert t in jq, "unused.jq does not report the type " + t
    assert t.split(" ")[0] in text, t
# the expected list: 10 objects of 9 types
expected = re.findall(r'"([A-Za-z ]+)\|', re.findall(r'UC_EXPECTED=\((.*?)\)\n', lib, re.S)[0])
assert len(expected) == 10 and len(set(expected)) == 9, (len(expected), len(set(expected)))
assert "10 objects of 9 types" in text and "**ten** objects" in text
# the claims of the experiment
for needle in ("never the simple routes by name", "A route that a disabled step would have run leaves nothing", "the log does not tell a skipped route", "So the search is by id, not by name.", "The search finds itself.",
               "AR0011", "AR0108", "Route step's execute route cannot be referenced more that once as an execute route.", "Account does not contain any PeSIT transfer sites.",
               "is the `status` of the **step** that runs it", "a trusted CA certificate has no owner and is never reported", "**8 calls, 22 objects", "**8 calls, 398 objects", "AS2 and PeSIT sites.",
               "A reference counts **even when it comes from an unused object**", "candidates", "Delete one object, run the steps again"):
    assert needle.lower() in text.lower(), needle
# the steps of the README are the files
for name in re.findall(r"`(\d\d\.[a-z]+_[a-z_A-Z]+)(?: \[[A-Z]+\])*`", text):
    assert __import__("os").path.exists(sys.argv[1].rsplit("/", 1)[0] + "/" + name + ".sh"), name
PY
echo
if [ "${FAILED}" -ne 0 ]; then echo "test_bash_admin_usecase_08: FAIL"; exit 1; fi
echo "test_bash_admin_usecase_08: PASS"
