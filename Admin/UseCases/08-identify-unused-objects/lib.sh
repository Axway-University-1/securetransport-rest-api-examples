#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL, the cookie jar session.cookie.jar of this use case and st_session) and gives the helpers the steps share:
#
#   uc_get RESOURCE [NAME=VALUE ...]      GET /RESOURCE with the query made of the NAME=VALUE pairs, each encoded; sets LIST_CODE and LIST_BODY
#   uc_why                                prints why the server refused the call in LIST_BODY
#   uc_post RESOURCE JSON                 POST; sets POST_LOCATION (the Location header); on any answer but 201 prints why and returns 1
#   uc_patch PATH JSON / uc_head PATH / uc_delete PATH     the other calls of the steps; they print the status they got and return 0 for the status expected
#   uc_id_of RESOURCE NAME                the id of the object of that exact name ("" when there is none)
#   uc_import_cert NAME ACCOUNT FILE PASSWORD   imports a PKCS#12 file as a private certificate of an account (multipart/mixed: the JSON, then the file)
#   uc_read_all LABEL RESOURCE [N=V ...]  reads a whole list, page by page (limit 100, offset), into $UC_MAP/LABEL.json and counts the calls, the objects and the seconds
#   uc_cost_start / uc_cost_line / uc_cost_total   print the cost of what was read
#   uc_build_map PREFIX DIR               reads what the rules need (7 kinds of object), with the cost; PREFIX "" is the whole server
#   uc_log_search DIR                     searches the server log, once for each route that only a disabled step runs, for the id of the route
#   uc_unused DIR                         the rules (unused.jq): one TSV line for each object: U (unused) or K (kept), type, name, why
#   uc_print_unused DIR                   the same grouped by type, with the totals
#   uc_check_prefix VALUE USAGE           exits 2 with the usage, before any call, when the prefix is not a name prefix
#
# The objects of this use case are example_unu_*: two accounts (a1 has all the relations, a2 none), their certificates, sites, transfer profiles, subscriptions, applications, route templates, simple routes and composite routes.
# UC_EXPECTED is the list of objects that must come out as unused, one line for each: "type|name".
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

ST_ENDUSER_PORT="${ST_ENDUSER_PORT:-$((ST_PORT - 1))}"
EU_URL="https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0"
PREFIX_DEFAULT="example_unu_"
MAP_DIR="${UC_DIR}/state.local.map"                 # what 07 and 08 read (the demo set, or the prefix given)
MAP_ALL_DIR="${UC_DIR}/state.local.mapall"          # what 10 reads (the whole server)
PASSWORD_FILE="${UC_DIR}/state.local.password"      # the password of the account a1 (01 writes it, git ignores it)
P12_PASSWORD="Ex1!p12-example"                      # the password of the throwaway PKCS#12 files of 01

A1="example_unu_a1"        # the account that has all the relations
A2="example_unu_a2"        # the account that has none
A1_UID=58201
A2_UID=58202
CERT_USED="example_unu_cert_used"
CERT_UNUSED="example_unu_cert_unused"
SITE_USED="example_unu_site_used"          # a subscription uses it (and it names a certificate)
SITE_STEP="example_unu_site_step"          # a route step uses it
SITE_UNUSED="example_unu_site_unused"
SITE_PESIT="example_unu_pesit_support"      # a PeSIT site: the server makes a transfer profile only for an account that has one. The use case skips PeSIT sites (see the README)
PROFILE_USED="example_unu_profile_used"
PROFILE_UNUSED="example_unu_profile_unused"
APP_USED="example_unu_app_used"
APP_UNUSED="example_unu_app_unused"
SUB_FOLDER="/example_unu_in"               # the subscription that has a site, a profile and a composite route
SUB_UNUSED_FOLDER="/example_unu_sub_unused"
TPL_USED="example_unu_tpl_used"
TPL_UNUSED="example_unu_tpl_unused"
RT_ON="example_unu_rt_on"                  # a simple route that an enabled step runs
RT_OLD="example_unu_rt_old"                # run in the past, disabled now
RT_NEVER="example_unu_rt_never"            # disabled, never run
RT_ORPHAN="example_unu_rt_orphan"          # no step runs it
COMP_USED="example_unu_comp_used"
COMP_UNUSED="example_unu_comp_unused"      # no subscription starts it

UC_EXPECTED=("Account|${A2}" "Application|${APP_UNUSED}" "Certificate|${CERT_UNUSED}" "Composite route|${COMP_UNUSED}" "Route|${RT_NEVER}" "Route|${RT_ORPHAN}"
             "Route template|${TPL_UNUSED}" "Site|${SITE_UNUSED}" "Subscription|${A1} ${SUB_UNUSED_FOLDER}" "Transfer profile|${PROFILE_UNUSED}")
UC_TYPES=("Account" "Application" "Certificate" "Composite route" "Route" "Route template" "Site" "Subscription" "Transfer profile")

uc_get() {
    local resource="$1" param result args=()
    shift
    for param in "$@"; do args+=(--data-urlencode "${param}"); done
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/${resource}" "${args[@]}" -H "accept: application/json" -H "Referer: ${REFERER}")
    LIST_CODE="${result: -3}"
    LIST_BODY="${result%???}"
}

uc_why() {
    printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${LIST_BODY}"
}

uc_post() {      # RESOURCE JSON: prints the Location; any other answer than 201 is a failure with the reason
    local headers result code
    headers=$(mktemp)
    result=$(curl -k -s -w "\n%{http_code}" -D "${headers}" -b "${JAR}" -X POST "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$2")
    code="${result##*$'\n'}"
    POST_LOCATION=$(tr -d '\r' < "${headers}" | sed -n 's/^[Ll]ocation: *//p')
    rm -f "${headers}"
    if [ "${code}" != "201" ]; then
        printf "POST /%s: HTTP %s\n" "$1" "${code}"
        printf '%s\n' "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${result%$'\n'*}"
        return 1
    fi
    printf "  HTTP 201, it is at %s\n" "${POST_LOCATION}"
}

uc_head() {      # PATH: the status of a HEAD
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}"
}

uc_patch() {     # PATH JSON: the status of a PATCH
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X PATCH "${ST_URL}/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$2"
}

uc_delete() {    # PATH: the status of a DELETE
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
}

uc_id_of() {     # RESOURCE NAME: the name filter looks for a pattern, so the exact name is picked from what it finds
    uc_get "$1" "name=$2" "fields=id,name"
    [ "${LIST_CODE}" = "200" ] || return 0
    printf '%s' "${LIST_BODY}" | jq -r --arg n "$2" '[(.result // [])[] | select(.name == $n)][0].id // empty'
}

uc_import_cert() {   # NAME ACCOUNT FILE PASSWORD: the status of the import; the id is read afterwards
    local body code
    body=$(mktemp)
    {
        printf -- '--BOUNDARY\r\nContent-Type: application/json\r\n\r\n'
        jq -cjn --arg name "$1" --arg account "$2" --arg password "$4" '{name: $name, type: "x509", usage: "private", account: $account, password: $password}'
        printf -- '\r\n--BOUNDARY\r\nContent-Type: application/octet-stream\r\n\r\n'
        cat "$3"
        printf -- '\r\n--BOUNDARY--\r\n'
    } > "${body}"
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/certificates" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "Content-Type: multipart/mixed; boundary=BOUNDARY" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" --data-binary "@${body}")
    rm -f "${body}"
    echo "${code}"
}

uc_check_prefix() {  # VALUE USAGE
    if [[ ! "$1" =~ ^[A-Za-z0-9_.][A-Za-z0-9_.-]*$ ]]; then
        printf "PREFIX is '%s': the beginning of the names to look at (letters, digits, _ . -, not empty, not starting with -), for example example_unu_.\n%s\n" "$1" "$2"
        exit 2
    fi
}

# ---- the cost -----------------------------------------------------------------------------------------------------------------------------------------
UC_CALLS=0; UC_OBJECTS=0; UC_SECONDS=0

uc_cost_start() { UC_CALLS=0; UC_OBJECTS=0; UC_SECONDS=0; }

# uc_cost_line LABEL CALLS OBJECTS SECONDS: one line of the cost table, and adds it to the total
uc_cost_line() {
    printf "  %-42s %5s %9s %8s\n" "$1" "$2" "$3" "$4"
    UC_CALLS=$((UC_CALLS + $2)); UC_OBJECTS=$((UC_OBJECTS + $3)); UC_SECONDS=$((UC_SECONDS + $4))
}

uc_cost_head() { printf "  %-42s %5s %9s %8s\n" "What was read" "calls" "objects" "seconds"; }
uc_cost_total() { printf "  %-42s %5s %9s %8s\n" "Total" "${UC_CALLS}" "${UC_OBJECTS}" "${UC_SECONDS}"; }

# uc_read_all LABEL RESOURCE [N=V ...]: the whole list in pages of 100; the objects go to $UC_MAP/LABEL.json (one array), the cost to the table.
# A page that is refused stops it with the code and the reason (return 1). It stops when a page is short or empty, or all totalCount objects are read.
uc_read_all() {
    local label="$1" resource="$2" offset=0 calls=0 objects=0 start total got
    shift 2
    start=$(date +%s)
    printf '[]' > "${UC_MAP}/${label}.json"
    while :; do
        uc_get "${resource}" "$@" "limit=100" "offset=${offset}"
        calls=$((calls + 1))
        if [ "${LIST_CODE}" != "200" ]; then
            printf "%s: HTTP %s: %s\n" "${label}" "${LIST_CODE}" "$(uc_why)"
            return 1
        fi
        got=$(printf '%s' "${LIST_BODY}" | jq -r '(.result // []) | length' 2>/dev/null)
        total=$(printf '%s' "${LIST_BODY}" | jq -r '.resultSet.totalCount // empty' 2>/dev/null)
        if [[ ! "${got}" =~ ^[0-9]+$ || ! "${total}" =~ ^[0-9]+$ ]]; then
            printf "%s: the answer has no result and no resultSet.totalCount, so there is nothing to read.\n" "${label}"
            return 1
        fi
        printf '%s' "${LIST_BODY}" | jq -c '.result // []' | jq -s -c '.[0] as $new | $old + $new' --argjson old "$(cat "${UC_MAP}/${label}.json")" > "${UC_MAP}/${label}.tmp" &&
            mv "${UC_MAP}/${label}.tmp" "${UC_MAP}/${label}.json"
        objects=$((objects + got))
        offset=$((offset + got))
        if [ "${got}" -eq 0 ] || [ "${offset}" -ge "${total}" ]; then break; fi
    done
    uc_cost_line "${label}" "${calls}" "${objects}" "$(( $(date +%s) - start ))"
}

# uc_build_map PREFIX DIR: PREFIX "" reads the whole server. With a prefix the lists are filtered by name (name=PREFIX*), so only those objects are read; the subscriptions have no name, so they are read for each account
uc_build_map() {
    local prefix="$1" account filter=() acc_filter=()
    UC_MAP="$2"
    mkdir -p "${UC_MAP}"
    rm -f "${UC_MAP}"/*.json "${UC_MAP}/prefix"
    printf '%s' "${prefix}" > "${UC_MAP}/prefix"
    [ -n "${prefix}" ] && filter=("name=${prefix}*")
    uc_cost_start
    uc_cost_head
    uc_read_all accounts accounts "${filter[@]}" "fields=name" || return 1
    uc_read_all applications applications "${filter[@]}" "fields=id,name" || return 1
    uc_read_all certificates certificates "${filter[@]}" "fields=id,name,usage,account" || return 1
    uc_read_all sites sites "${filter[@]}" "fields=id,name,account,protocol,clientCertificate,loginCertificate,partnerCertificate" || return 1
    uc_read_all profiles transferProfiles "${filter[@]}" "fields=id,name,account,default" || return 1
    uc_read_all routes routes "${filter[@]}" || return 1
    if [ -z "${prefix}" ]; then
        uc_read_all subscriptions subscriptions "fields=id,account,application,folder,transferConfigurations" || return 1
    else
        printf '[]' > "${UC_MAP}/subscriptions.json"
        local calls=0 objects=0 start n
        start=$(date +%s)
        for account in $(jq -r '.[].name' "${UC_MAP}/accounts.json"); do
            uc_get subscriptions "account=${account}" "fields=id,account,application,folder,transferConfigurations" "limit=100"
            calls=$((calls + 1))
            if [ "${LIST_CODE}" != "200" ]; then printf "subscriptions of %s: HTTP %s: %s\n" "${account}" "${LIST_CODE}" "$(uc_why)"; return 1; fi
            n=$(printf '%s' "${LIST_BODY}" | jq -r '(.result // []) | length')
            objects=$((objects + n))
            printf '%s' "${LIST_BODY}" | jq -c '.result // []' | jq -s -c '.[0] as $new | $old + $new' --argjson old "$(cat "${UC_MAP}/subscriptions.json")" > "${UC_MAP}/subscriptions.tmp" &&
                mv "${UC_MAP}/subscriptions.tmp" "${UC_MAP}/subscriptions.json"
        done
        uc_cost_line "subscriptions (one call for each account)" "${calls}" "${objects}" "$(( $(date +%s) - start ))"
    fi
    uc_cost_total
}

# uc_log_search DIR: for every simple route that is run only by disabled steps, one call to the server log for its id. The log records the administrator's own requests too, and each of them holds
# the text that was asked for, so an entry that holds "/api/v2.0/" is the search itself and does not count. Writes DIR/logsearch.tsv: id, name, found (1 or 0), entries that count, entries ignored.
uc_log_search() {
    local dir="$1" id name entries ignored found calls=0 start
    UC_MAP="${dir}"
    : > "${dir}/logsearch.tsv"
    start=$(date +%s)
    while IFS=$'\t' read -r id name; do
        [ -n "${id}" ] || continue
        uc_get logs/server "message=${id}" "limit=100"
        calls=$((calls + 1))
        if [ "${LIST_CODE}" != "200" ]; then
            printf "The server log, for %s: HTTP %s: %s\n" "${name}" "${LIST_CODE}" "$(uc_why)"
            return 1
        fi
        entries=$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/") | not)] | length')
        ignored=$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/"))] | length')
        found=0; [ "${entries}" -gt 0 ] && found=1
        printf '%s\t%s\t%s\t%s\t%s\n' "${id}" "${name}" "${found}" "${entries}" "${ignored}" >> "${dir}/logsearch.tsv"
        if [ "${found}" = 1 ]; then
            printf "  %s: found, %s entries that name it (the first: %s)\n" "${name}" "${entries}" \
                "$(printf '%s' "${LIST_BODY}" | jq -r '[(.result // [])[] | select((.message // "") | contains("/api/v2.0/") | not)][0].message[0:110]')"
        else
            printf "  %s: not found (%s entries were only the administrator's own requests for this search)\n" "${name}" "${ignored}"
        fi
    done < <(jq -r '[.[] | select(.type == "COMPOSITE" or .type == "TEMPLATE") | (.steps // [])[] | select(.type == "ExecuteRoute")] as $steps
                    | ([$steps[] | select(.status == "ENABLED") | .executeRoute]) as $on
                    | [$steps[] | select(.status != "ENABLED") | .executeRoute] | unique | map(select(. as $r | $on | index($r) | not))[] as $id
                    | [$id, ([$routes[] | select(.id == $id) | .name][0] // $id)] | @tsv' --argjson routes "$(cat "${dir}/routes.json")" "${dir}/routes.json")
    printf "  %s call(s) to the server log, %s s.\n" "${calls}" "$(( $(date +%s) - start ))"
}

# uc_unused DIR: the rules. TSV: U or K, the type, the name, why
uc_unused() {
    local dir="$1" found='{}'
    if [ -s "${dir}/logsearch.tsv" ]; then
        found=$(jq -Rn '[inputs | split("\t") | select(.[2] == "1") | {(.[0]): true}] | add // {}' "${dir}/logsearch.tsv")
    fi
    jq -r -f "${UC_DIR}/unused.jq" --slurpfile accounts "${dir}/accounts.json" --slurpfile apps "${dir}/applications.json" --slurpfile certs "${dir}/certificates.json" \
        --slurpfile sites "${dir}/sites.json" --slurpfile profiles "${dir}/profiles.json" --slurpfile subs "${dir}/subscriptions.json" --slurpfile routes "${dir}/routes.json" \
        --argjson found "${found}" -n
}

# uc_print_unused DIR: the unused objects grouped by type, then the kept ones, then the totals
uc_print_unused() {
    local rows type n total=0 kinds=0
    rows=$(uc_unused "$1") || return 1
    echo "Unused objects"
    for type in "${UC_TYPES[@]}"; do
        n=$(printf '%s\n' "${rows}" | awk -F'\t' -v t="${type}" '$1 == "U" && $2 == t' | wc -l | tr -d ' ')
        [ "${n}" -gt 0 ] || continue
        printf "  %s (%s)\n" "${type}" "${n}"
        printf '%s\n' "${rows}" | awk -F'\t' -v t="${type}" '$1 == "U" && $2 == t {printf "    %s  (%s)\n", $3, $4}' | sort
        total=$((total + n)); kinds=$((kinds + 1))
    done
    printf "Total: %s unused objects of %s types.\n" "${total}" "${kinds}"
    n=$(printf '%s\n' "${rows}" | awk -F'\t' '$1 == "K"' | wc -l | tr -d ' ')
    if [ "${n}" -gt 0 ]; then
        printf "Kept, although disabled now (%s):\n" "${n}"
        printf '%s\n' "${rows}" | awk -F'\t' '$1 == "K" {printf "    %s  (%s)\n", $3, $4}' | sort
    fi
}
