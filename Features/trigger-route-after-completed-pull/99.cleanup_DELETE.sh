#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Removes what the other examples created: the three routes, the subscription,
# the application, the two transfer sites, then the test account.
#
# Usage:
# ./99.cleanup_DELETE.sh [ACCOUNT]
#
#   ACCOUNT  the test account to remove (default arTestAccount). Use the same name
#            given to 00.run_all.sh, which prints it when it is not the default.
#
# Risk: write
#
# Notes:
# - Deletes the objects named in settings.sh, on the account named there. Check
#   the names before running it.
# - Everything is found by name, by listing the collection page by page, so it
#   works even if the ids saved by the earlier examples are gone. Anything that
#   is already gone (HTTP 404) is reported and skipped.
# - The folders in AR_CLEAN_FOLDERS (outbound-drop and delivered, which step 4 made,
#   and subscription) are emptied and removed first, as the account itself, so the account has
#   to exist and AR_ACCOUNT_PASSWORD has to be set. Without it they stay.
# - Deleting an account does NOT delete the files in its home folder. A new
#   account with the same home folder will find them. Delete them with the End
#   User API (EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh) if you
#   want an empty start.
# - Confirmed directly (5.5-20260924): GET and DELETE of a folder that does not exist are both a 404
#   (also directly in a home folder left by an account of another uid), which is why a 404 is "gone"
#   and a 403 is "refused".
# - Exits 1 when something could not be deleted (the server refused, or a list
#   could not be read), and says what is left. The saved ids in state.local.sh are
#   then kept, and running it again tries again. Only when everything is gone is
#   the file removed.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
[ "$#" -gt 1 ] && { printf "Usage: ./99.cleanup_DELETE.sh [ACCOUNT]\n"; exit 2; }
if [ -n "$1" ]; then
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "$1"; exit 2; }
    export AR_RUN_ACCOUNT="$1"
fi
source "${SCRIPT_DIR}/settings.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
BASE_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
PAGE_SIZE=100

# What could not be deleted, one line each, for the summary at the end
NOT_DELETED=()

# delete_all COLLECTION QUERY SELECT OUTPUT
#   Lists COLLECTION page by page (QUERY is extra query string, or empty), keeps the
#   objects that SELECT (a jq condition) matches, and deletes each by OUTPUT (a jq
#   expression for the id or name). The ids are found first, then deleted, so that
#   deleting does not shift the pages. A list the server refuses, and a delete it
#   refuses (other than a 404, which means it is gone), go on NOT_DELETED.
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
          --arg account "${AR_TEST_ACCOUNT}" --arg pull "${AR_PULL_SITE}" --arg push "${AR_PUSH_SITE}" \
          --arg composite "${AR_COMPOSITE_ROUTE}" --arg simple "${AR_SIMPLE_ROUTE}" \
          --arg template "${AR_TEMPLATE_ROUTE}" --arg app "${AR_APPLICATION}" \
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

# remove_folders
#   Empties and removes the folders in AR_CLEAN_FOLDERS from the account's home, with
#   the End User API, logged in as the account. Do it while the account still exists.
remove_folders() {
    local folder name
    if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
        printf "AR_ACCOUNT_PASSWORD is not set, so the folders are left in place.\n"
        return
    fi
    if ! ar_enduser_login; then
        printf "The folders are left in place.\n"
        NOT_DELETED+=("the folders ${AR_CLEAN_FOLDERS} in the home of ${AR_TEST_ACCOUNT} (could not log in)")
        return
    fi
    for folder in ${AR_CLEAN_FOLDERS}; do
        ar_enduser_call GET "files/${folder}" ""
        if [ "${AR_EU_CODE}" = "404" ]; then
            printf "The folder %s is not there.\n" "${folder}"
            continue
        fi
        while IFS= read -r name; do
            [ -z "${name}" ] && continue
            printf "Deleting the file %s/%s...\n" "${folder}" "${name}"
            delete_folder_item "the file ${folder}/${name}" "files/${folder}/${name}"
        done < <(printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | .fileName' 2>/dev/null)
        printf "Deleting the folder %s...\n" "${folder}"
        delete_folder_item "the folder ${folder}" "files/${folder}"
    done
    ar_enduser_logout
}

# The composite route refers to the others, so it goes first
delete_all routes "type=COMPOSITE&" '.name == $composite' '.id'
delete_all routes "type=SIMPLE&"    '.name == $simple'    '.id'
delete_all routes "type=TEMPLATE&"  '.name == $template'  '.id'
delete_all subscriptions "" '.account == $account and .application == $app' '.id'
delete_all applications  "" '.name == $app' '.name'
delete_all sites "" '.account == $account and (.name == $pull or .name == $push)' '.id'

ar_admin_exists "accounts/${AR_TEST_ACCOUNT}"
case $? in
    0)
        remove_folders
        printf "Deleting the account %s...\n" "${AR_TEST_ACCOUNT}"
        if ! ar_admin_delete "accounts/${AR_TEST_ACCOUNT}" && [ "${AR_ADMIN_CODE}" != "404" ]; then
            NOT_DELETED+=("the account ${AR_TEST_ACCOUNT} (HTTP ${AR_ADMIN_CODE})")
        fi
        ;;
    1)
        printf "The account %s does not exist (HTTP %s). Nothing to delete.\n" "${AR_TEST_ACCOUNT}" "${AR_ADMIN_CODE}"
        ;;
    *)
        printf "Could not tell whether the account %s exists (HTTP %s).\n" "${AR_TEST_ACCOUNT}" "${AR_ADMIN_CODE}"
        NOT_DELETED+=("the account ${AR_TEST_ACCOUNT} and its folders (could not check that it exists, HTTP ${AR_ADMIN_CODE})")
        ;;
esac

if [ "${#NOT_DELETED[@]}" -gt 0 ]; then
    printf "\nNot everything was removed. Left on the server:\n"
    for item in "${NOT_DELETED[@]}"; do
        printf "  %s\n" "${item}"
    done
    printf "The saved ids in %s are kept. Fix the cause, then run ./99.cleanup_DELETE.sh%s again.\n" \
      "${AR_STATE_FILE}" "$([ "${AR_TEST_ACCOUNT}" = "${AR_DEFAULT_ACCOUNT}" ] || printf ' %s' "${AR_TEST_ACCOUNT}")"
    exit 1
fi

rm -f "${AR_STATE_FILE}"
