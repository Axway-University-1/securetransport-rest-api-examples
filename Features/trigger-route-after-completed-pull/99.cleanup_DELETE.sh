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
# ./99.cleanup_DELETE.sh
#
# Notes:
# - Deletes the objects named in settings.sh, on the account named there. Check
#   the names before running it.
# - Everything is found by name, by listing the collection page by page, so it
#   works even if the ids saved by the earlier examples are gone. Anything that
#   is already gone is reported and skipped.
# - The folders in AR_CLEAN_FOLDERS (outbound-drop and delivered, which step 4 made,
#   and subscription) are emptied and removed first, as the account itself, so the account has
#   to exist and AR_ACCOUNT_PASSWORD has to be set. Without it they stay.
# - Deleting an account does NOT delete the files in its home folder. A new
#   account with the same home folder will find them. Delete them with the End
#   User API (EndUser/API 2.0/bash/02.Files/07.files_filepath_DELETE.sh) if you
#   want an empty start.
# - Requires `jq`.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
BASE_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
PAGE_SIZE=100

# delete_all COLLECTION QUERY SELECT OUTPUT
#   Lists COLLECTION page by page (QUERY is extra query string, or empty), keeps the
#   objects that SELECT (a jq condition) matches, and deletes each by OUTPUT (a jq
#   expression for the id or name). The ids are found first, then deleted, so that
#   deleting does not shift the pages.
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
          --arg account "${AR_TEST_ACCOUNT}" --arg pull "${AR_PULL_SITE}" --arg push "${AR_PUSH_SITE}" \
          --arg composite "${AR_COMPOSITE_ROUTE}" --arg simple "${AR_SIMPLE_ROUTE}" \
          --arg template "${AR_TEMPLATE_ROUTE}" --arg app "${AR_APPLICATION}" \
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

# remove_folders
#   Empties and removes the folders in AR_CLEAN_FOLDERS from the account's home, with
#   the End User API, logged in as the account. Do it while the account still exists.
remove_folders() {
    local folder name
    if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
        printf "AR_ACCOUNT_PASSWORD is not set, so the folders are left in place.\n"
        return
    fi
    ar_enduser_login || { printf "The folders are left in place.\n"; return; }
    for folder in ${AR_CLEAN_FOLDERS}; do
        ar_enduser_call GET "files/${folder}" ""
        while IFS= read -r name; do
            [ -z "${name}" ] && continue
            printf "Deleting the file %s/%s...\n" "${folder}" "${name}"
            ar_enduser_call DELETE "files/${folder}/${name}" ""
            printf "HTTP %s\n" "${AR_EU_CODE}"
        done < <(printf '%s' "${AR_EU_BODY}" | jq -r '(.files // [])[] | select(.isRegularFile) | .fileName' 2>/dev/null)
        printf "Deleting the folder %s...\n" "${folder}"
        ar_enduser_call DELETE "files/${folder}" ""
        printf "HTTP %s\n" "${AR_EU_CODE}"
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

ACCOUNT_CODE=$(curl -s -k -o /dev/null -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" --head \
  "${BASE_URL}/accounts/${AR_TEST_ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}")
case "${ACCOUNT_CODE}" in
    2*)
        remove_folders
        printf "Deleting the account %s...\n" "${AR_TEST_ACCOUNT}"
        curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${BASE_URL}/accounts/${AR_TEST_ACCOUNT}" \
          -H "accept: */*" -H "${REFERER_HEADER}" -w "\nHTTP %{http_code}\n"
        ;;
    *)
        printf "The account %s does not exist (HTTP %s). Nothing to delete.\n" "${AR_TEST_ACCOUNT}" "${ACCOUNT_CODE}"
        ;;
esac

rm -f "${AR_STATE_FILE}"
