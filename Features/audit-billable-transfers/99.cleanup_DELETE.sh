#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Removes everything the other examples created: the composite routes, the
# simple routes, the template, the subscriptions, the application, the eight
# sites, the folders in the test account's home, the test account itself, and
# then this test account's folder in each partner. A partner account is deleted
# too, once no other test account's site logs in as it any more.
#
# Usage:
# ./99.cleanup_DELETE.sh [ACCOUNT]
#
#   ACCOUNT  the test account to remove, with everything derived from its name
#            (default btTestAccount). Use the same name given to 00.run_all.sh.
#
# Notes:
# - Deletes the objects named in settings.sh, on the account named there. Check
#   the names before running it.
# - Everything is found by name, by listing the collection page by page, so it
#   works even if the ids saved by the earlier examples are gone. Anything
#   already gone is reported and skipped.
# - The folders are emptied and removed while their account still exists, so it
#   needs settings.local.sh with BT_ACCOUNT_PASSWORD. Without it, they are left
#   in place and only the accounts are deleted.
# - The partners are shared by every test account. Only this test account's own
#   folder in them is removed, and a partner stays while another test account's
#   site still logs in as it.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
if [ -n "$1" ]; then
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "$1"; exit 2; }
    export BT_RUN_ACCOUNT="$1"
fi
source "${SCRIPT_DIR}/settings.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
BASE_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
PAGE_SIZE=100

# delete_all COLLECTION QUERY SELECT OUTPUT
#   Lists COLLECTION page by page (QUERY is extra query string, or empty), keeps
#   the objects that SELECT (a jq condition) matches, and deletes each by OUTPUT
#   (a jq expression for the id or name). The ids are found first, then deleted,
#   so that deleting does not shift the pages.
delete_all() {
    local collection="$1" query="$2" select="$3" output="$4" offset=0 page count id
    local ids=()
    while true; do
        page=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
          "${BASE_URL}/${collection}?${query}offset=${offset}&limit=${PAGE_SIZE}" \
          -H "accept: application/json" -H "${REFERER_HEADER}")
        while IFS= read -r id; do
            [ -n "${id}" ] && ids+=("${id}")
        done < <(printf '%s' "${page}" | jq -r \
          --arg account "${BT_TEST_ACCOUNT}" --arg app "${BT_APPLICATION}" \
          --arg composite_prefix "${BT_COMPOSITE_ROUTE_PREFIX}" \
          --arg simple_prefix "${BT_SIMPLE_ROUTE_PREFIX}" \
          --arg pull_prefix "${BT_PULL_SITE_PREFIX}" \
          --arg push1 "${BT_PUSH_SITE_1}" --arg push2 "${BT_PUSH_SITE_2}" \
          --arg template "${BT_TEMPLATE_ROUTE}" \
          "(.result // [])[] | select(${select}) | ${output}" 2>/dev/null)
        count=$(printf '%s' "${page}" | jq -r '(.result // []) | length' 2>/dev/null)
        [ -z "${count}" ] && break
        [ "${count}" -lt "${PAGE_SIZE}" ] && break
        offset=$((offset + PAGE_SIZE))
    done

    if [ "${#ids[@]}" -eq 0 ]; then
        printf "No %s to delete.\n" "${collection}"
        return
    fi
    for id in "${ids[@]}"; do
        printf "Deleting %s %s...\n" "${collection}" "${id}"
        curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${BASE_URL}/${collection}/${id}" \
          -H "accept: */*" -H "${REFERER_HEADER}" -w "\nHTTP %{http_code}\n"
    done
}

# remove_folders ACCOUNT FOLDER...: empties and removes each folder, in order,
# with the End User API, logged in as ACCOUNT. Do it while the account exists.
remove_folders() {
    local account="$1" folder name
    shift
    if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
        printf "BT_ACCOUNT_PASSWORD is not set, so the folders of %s are left in place.\n" "${account}"
        return
    fi
    bt_login_as "${account}" || { printf "The folders of %s are left in place.\n" "${account}"; return; }
    for folder in "$@"; do
        ar_enduser_call GET "files${folder}" ""
        while IFS= read -r name; do
            [ -z "${name}" ] && continue
            printf "Deleting the file %s/%s...\n" "${folder}" "${name}"
            ar_enduser_call DELETE "files${folder}/${name}" ""
            printf "HTTP %s\n" "${AR_EU_CODE}"
        done < <(printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | .fileName' 2>/dev/null)
        printf "Deleting the folder %s of %s...\n" "${folder}" "${account}"
        ar_enduser_call DELETE "files${folder}" ""
        printf "HTTP %s\n" "${AR_EU_CODE}"
    done
    ar_enduser_logout
}

# account_exists ACCOUNT
account_exists() {
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" --head \
      "${BASE_URL}/accounts/$1" -H "accept: */*" -H "${REFERER_HEADER}")
    [ "${code}" = "200" ]
}

# delete_account ACCOUNT
delete_account() {
    printf "Deleting the account %s...\n" "$1"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${BASE_URL}/accounts/$1" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\nHTTP %{http_code}\n"
}

# sites_logging_in_as ACCOUNT: how many sites, of any account, log in as it
sites_logging_in_as() {
    local offset=0 page count total=0 n
    while true; do
        page=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
          "${BASE_URL}/sites?offset=${offset}&limit=${PAGE_SIZE}" \
          -H "accept: application/json" -H "${REFERER_HEADER}")
        n=$(printf '%s' "${page}" | jq -r --arg partner "$1" \
          '[(.result // [])[] | select(.userName == $partner)] | length' 2>/dev/null)
        total=$((total + ${n:-0}))
        count=$(printf '%s' "${page}" | jq -r '(.result // []) | length' 2>/dev/null)
        [ -z "${count}" ] && break
        [ "${count}" -lt "${PAGE_SIZE}" ] && break
        offset=$((offset + PAGE_SIZE))
    done
    printf '%s' "${total}"
}

# The composite routes refer to the simple routes, so they go first
delete_all routes "type=COMPOSITE&" '(.name // "") | startswith($composite_prefix)' '.id'
delete_all routes "type=SIMPLE&"    '(.name // "") | startswith($simple_prefix)'    '.id'
delete_all routes "type=TEMPLATE&"  '.name == $template'                            '.id'
delete_all subscriptions "" '.account == $account and .application == $app' '.id'
delete_all applications  "" '.name == $app' '.name'
delete_all sites "" '.account == $account and ((.name // "") | startswith($pull_prefix) or . == $push1 or . == $push2)' '.id'

# The test account: its folders, then the account
if account_exists "${BT_TEST_ACCOUNT}"; then
    folders=()
    for n in 1 2 3 4 5 6; do
        folders+=("${BT_SUBSCRIPTION_FOLDER}/s${n}")
    done
    remove_folders "${BT_TEST_ACCOUNT}" "${folders[@]}" "${BT_SUBSCRIPTION_FOLDER}"
    delete_account "${BT_TEST_ACCOUNT}"
else
    printf "The account %s does not exist. Nothing to delete.\n" "${BT_TEST_ACCOUNT}"
fi

# The partners: this test account's folder in each, then the partner itself,
# unless another test account's site still logs in as it
for partner in "${BT_PULL_PARTNER}" "${BT_PUSH_PARTNER}"; do
    if ! account_exists "${partner}"; then
        printf "The account %s does not exist. Nothing to delete.\n" "${partner}"
        continue
    fi
    if [ "${partner}" = "${BT_PULL_PARTNER}" ]; then
        remove_folders "${partner}" "${BT_DROP_FOLDER}" "${BT_RUN_FOLDER}"
    else
        remove_folders "${partner}" "${BT_DELIVERED_1_FOLDER}" "${BT_DELIVERED_2_FOLDER}" "${BT_RUN_FOLDER}"
    fi
    in_use=$(sites_logging_in_as "${partner}")
    if [ "${in_use}" -gt 0 ]; then
        printf "The account %s is kept: %s site(s) of another test account still log in as it.\n" "${partner}" "${in_use}"
    else
        delete_account "${partner}"
    fi
done

rm -f "${AR_STATE_FILE}"
