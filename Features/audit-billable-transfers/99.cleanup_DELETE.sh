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
# Risk: write
#
# Notes:
# - Deletes the objects named in settings.sh, on the account named there. Check
#   the names before running it.
# - Everything is found by name, by listing the collection page by page, so it
#   works even if the ids saved by the earlier examples are gone. Anything
#   already gone (HTTP 404) is reported and skipped.
# - The folders are emptied and removed while their account still exists, so it
#   needs settings.local.sh with BT_ACCOUNT_PASSWORD. Without it, they are left
#   in place and only the accounts are deleted.
# - The partners are shared by every test account. Only this test account's own
#   folder in them is removed, and a partner stays while another test account's
#   site still logs in as it.
# - Confirmed directly (5.5-20260924): GET and DELETE of a folder that does not exist are both a 404
#   (also directly in a home folder left by an account of another uid), which is why a 404 is "gone"
#   and a 403 is "refused".
# - Exits 1 when something could not be deleted (the server refused, a list could not
#   be read, a folder or account could not be checked), and says what is left. The
#   saved ids in state.local.sh are then kept, and running it again tries again. Only
#   when everything is gone is the file removed. A partner is never deleted when the
#   list of sites that log in as it could not be read.
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

# What could not be deleted, one line each, for the summary at the end
NOT_DELETED=()

# delete_all COLLECTION QUERY SELECT OUTPUT
#   Lists COLLECTION page by page (QUERY is extra query string, or empty), keeps
#   the objects that SELECT (a jq condition) matches, and deletes each by OUTPUT
#   (a jq expression for the id or name). The ids are found first, then deleted,
#   so that deleting does not shift the pages. A list the server refuses, and a
#   delete it refuses (other than a 404, which means it is gone), go on NOT_DELETED.
delete_all() {
    local collection="$1" query="$2" select="$3" output="$4" offset=0 page count id hdr code
    local ids=()
    hdr=$(mktemp)
    while true; do
        page=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
          "${BASE_URL}/${collection}?${query}offset=${offset}&limit=${PAGE_SIZE}" \
          -H "accept: application/json" -H "${REFERER_HEADER}" -D "${hdr}")
        code=$(head -n 1 "${hdr}" | awk '{print $2}')
        case "${code}" in
            2*) ;;
            *)
                printf "The list of %s could not be read (HTTP %s), so none of them was deleted.\n" "${collection}" "${code:-000}"
                NOT_DELETED+=("${collection}: the list could not be read (HTTP ${code:-000})")
                rm -f "${hdr}"
                return
                ;;
        esac
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
    rm -f "${hdr}"

    if [ "${#ids[@]}" -eq 0 ]; then
        printf "No %s to delete.\n" "${collection}"
        return
    fi
    for id in "${ids[@]}"; do
        printf "Deleting %s %s...\n" "${collection}" "${id}"
        if ! ar_admin_delete "${collection}/${id}" && [ "${AR_ADMIN_CODE}" != "404" ]; then
            NOT_DELETED+=("${collection} ${id} (HTTP ${AR_ADMIN_CODE})")
        fi
    done
}

# delete_folder_item DESCRIPTION PATH: DELETE one file or folder as the logged in
# account. A refused delete, other than a 404, goes on NOT_DELETED.
delete_folder_item() {
    ar_enduser_call DELETE "$2" ""
    printf "HTTP %s\n" "${AR_EU_CODE}"
    if [ "${AR_EU_CODE:0:1}" != "2" ] && [ "${AR_EU_CODE}" != "404" ]; then
        NOT_DELETED+=("$1 (HTTP ${AR_EU_CODE})")
    fi
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
    if ! bt_login_as "${account}"; then
        printf "The folders of %s are left in place.\n" "${account}"
        NOT_DELETED+=("the folders of ${account} (could not log in): $*")
        return
    fi
    for folder in "$@"; do
        ar_enduser_call GET "files${folder}" ""
        if [ "${AR_EU_CODE}" = "404" ]; then
            printf "The folder %s of %s is not there.\n" "${folder}" "${account}"
            continue
        fi
        while IFS= read -r name; do
            [ -z "${name}" ] && continue
            printf "Deleting the file %s/%s...\n" "${folder}" "${name}"
            delete_folder_item "the file ${folder}/${name} of ${account}" "files${folder}/${name}"
        done < <(printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | .fileName' 2>/dev/null)
        printf "Deleting the folder %s of %s...\n" "${folder}" "${account}"
        delete_folder_item "the folder ${folder} of ${account}" "files${folder}"
    done
    ar_enduser_logout
}

# delete_account ACCOUNT: a refused delete, other than a 404, goes on NOT_DELETED
delete_account() {
    printf "Deleting the account %s...\n" "$1"
    if ! ar_admin_delete "accounts/$1" && [ "${AR_ADMIN_CODE}" != "404" ]; then
        NOT_DELETED+=("the account $1 (HTTP ${AR_ADMIN_CODE})")
    fi
}

# sites_logging_in_as ACCOUNT: prints how many sites, of any account, log in as it.
# Returns 1 (and prints nothing) when a page of the list could not be read: then
# nobody knows, and the partner must not be deleted.
sites_logging_in_as() {
    local offset=0 page count total=0 n hdr code
    hdr=$(mktemp)
    while true; do
        page=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET \
          "${BASE_URL}/sites?offset=${offset}&limit=${PAGE_SIZE}" \
          -H "accept: application/json" -H "${REFERER_HEADER}" -D "${hdr}")
        code=$(head -n 1 "${hdr}" | awk '{print $2}')
        case "${code}" in
            2*) ;;
            *) rm -f "${hdr}"; return 1 ;;
        esac
        n=$(printf '%s' "${page}" | jq -r --arg partner "$1" \
          '[(.result // [])[] | select(.userName == $partner)] | length' 2>/dev/null)
        total=$((total + ${n:-0}))
        count=$(printf '%s' "${page}" | jq -r '(.result // []) | length' 2>/dev/null)
        [ -z "${count}" ] && break
        [ "${count}" -lt "${PAGE_SIZE}" ] && break
        offset=$((offset + PAGE_SIZE))
    done
    rm -f "${hdr}"
    printf '%s' "${total}"
}

# The composite routes refer to the simple routes, so they go first
delete_all routes "type=COMPOSITE&" '(.name // "") | startswith($composite_prefix)' '.id'
delete_all routes "type=SIMPLE&"    '(.name // "") | startswith($simple_prefix)'    '.id'
delete_all routes "type=TEMPLATE&"  '.name == $template'                            '.id'
delete_all subscriptions "" '.account == $account and .application == $app' '.id'
delete_all applications  "" '.name == $app' '.name'
delete_all sites "" '.account == $account and ((.name // "") | startswith($pull_prefix) or . == $push1 or . == $push2)' '.id'

# account_state ACCOUNT: sets ACCOUNT_STATE to there, gone or unknown (the server did
# not say, so nothing may be assumed)
account_state() {
    ar_admin_exists "accounts/$1"
    case $? in
        0) ACCOUNT_STATE=there ;;
        1) ACCOUNT_STATE=gone ;;
        *) ACCOUNT_STATE=unknown ;;
    esac
}

# The test account: its folders, then the account
account_state "${BT_TEST_ACCOUNT}"
case "${ACCOUNT_STATE}" in
    there)
        folders=()
        for n in 1 2 3 4 5 6; do
            folders+=("${BT_SUBSCRIPTION_FOLDER}/s${n}")
        done
        remove_folders "${BT_TEST_ACCOUNT}" "${folders[@]}" "${BT_SUBSCRIPTION_FOLDER}"
        delete_account "${BT_TEST_ACCOUNT}"
        ;;
    gone)
        printf "The account %s does not exist. Nothing to delete.\n" "${BT_TEST_ACCOUNT}"
        ;;
    *)
        printf "Could not tell whether the account %s exists (HTTP %s).\n" "${BT_TEST_ACCOUNT}" "${AR_ADMIN_CODE}"
        NOT_DELETED+=("the account ${BT_TEST_ACCOUNT} and its folders (could not check that it exists, HTTP ${AR_ADMIN_CODE})")
        ;;
esac

# The partners: this test account's folder in each, then the partner itself,
# unless another test account's site still logs in as it
for partner in "${BT_PULL_PARTNER}" "${BT_PUSH_PARTNER}"; do
    account_state "${partner}"
    case "${ACCOUNT_STATE}" in
        gone)
            printf "The account %s does not exist. Nothing to delete.\n" "${partner}"
            continue
            ;;
        unknown)
            printf "Could not tell whether the account %s exists (HTTP %s).\n" "${partner}" "${AR_ADMIN_CODE}"
            NOT_DELETED+=("this test account's folders in ${partner} (could not check that it exists, HTTP ${AR_ADMIN_CODE})")
            continue
            ;;
    esac
    if [ "${partner}" = "${BT_PULL_PARTNER}" ]; then
        remove_folders "${partner}" "${BT_DROP_FOLDER}" "${BT_RUN_FOLDER}"
    else
        remove_folders "${partner}" "${BT_DELIVERED_1_FOLDER}" "${BT_DELIVERED_2_FOLDER}" "${BT_RUN_FOLDER}"
    fi
    if ! in_use=$(sites_logging_in_as "${partner}"); then
        printf "The list of sites could not be read, so the account %s is kept.\n" "${partner}"
        NOT_DELETED+=("the account ${partner}: not deleted, because the list of sites that log in as it could not be read")
        continue
    fi
    if [ "${in_use}" -gt 0 ]; then
        printf "The account %s is kept: %s site(s) of another test account still log in as it.\n" "${partner}" "${in_use}"
    else
        delete_account "${partner}"
    fi
done

if [ "${#NOT_DELETED[@]}" -gt 0 ]; then
    printf "\nNot everything was removed. Left on the server:\n"
    for item in "${NOT_DELETED[@]}"; do
        printf "  %s\n" "${item}"
    done
    printf "The saved ids in %s are kept. Fix the cause, then run ./99.cleanup_DELETE.sh %s again.\n" \
      "${AR_STATE_FILE}" "${BT_TEST_ACCOUNT}"
    exit 1
fi

rm -f "${AR_STATE_FILE}"
