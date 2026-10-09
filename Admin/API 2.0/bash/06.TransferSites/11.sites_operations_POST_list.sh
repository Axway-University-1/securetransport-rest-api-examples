#!/bin/bash
# ==============================================================================
# Script Name: 11.sites_operations_POST_list.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script lists a folder on the partner of a saved transfer site, using the
# `/sites/operations` endpoint with operation=listRemoteFolder: the server connects, logs
# in, lists the site's download (or upload) folder, and prints what it finds.
#
# Usage:
# ./11.sites_operations_POST_list.sh [ACCOUNT [NAME [FOLDER [LIMIT [FOLDERS]]]]]
#
#   ACCOUNT  the account the site belongs to (default john, or ST_EXAMPLE_ACCOUNT)
#   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.sh creates)
#   FOLDER   downloadFolder or uploadFolder (default downloadFolder)
#   LIMIT    how many entries to list, -1 for all (default 20)
#   FOLDERS  true to list the folders too, false for the files only (default true)
#
# Risk: read - opens a connection to the partner, changes nothing
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - SSH, FTP and HTTP sites can be listed this way (the reference says SSH and FTP; an HTTP
#   site lists the partner's folder too). The site's saved login is used; nothing secret is sent.
# - Confirmed directly: the folder named by the site is listed (`remoteFolder` in the answer),
#   and the answer carries `resultSet` and `result` like a collection, with the entries' name,
#   size (text such as "12.00 bytes"), permissions and last modified time. Leaving
#   `folderToList` out lists the UPLOAD folder, not the download folder the reference gives as
#   its default; so does a value other than downloadFolder. The script always sends it.
# - A folder that does not exist is still 200, with `remoteFolder` set, an empty result, and
#   `errorDetails` "No such file: Specified file path is invalid.". A site with no folder of
#   the kind asked for is 400 "Remote folder value cannot be empty for a non saved site." (the
#   text says "non saved" though the site is saved); a `limit` that is not a number is a bare 404.
#   `includesFolderNamesInResult` is not true by default either: left out, the folders are
#   missing from the answer (the reference says true), so the script always sends it.
#   `orderByLastModified=ascending` or `descending` sorts by time (listed by name otherwise).
#   `limit=-1` lists all; the reference gives 50 as the default (the option
#   ListRemoteFolder.Result.Files.Limit).
# - Requires `jq`, which reads the id and prints one line per entry.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"
ACCOUNT="${1:-${ST_EXAMPLE_ACCOUNT:-john}}"
NAME="${2:-SSH_PULL}"
FOLDER_TO_LIST="${3:-downloadFolder}"
[[ "${FOLDER_TO_LIST}" =~ ^(downloadFolder|uploadFolder)$ ]] || { printf "FOLDER is downloadFolder or uploadFolder, not %s.\n" "${FOLDER_TO_LIST}"; exit 2; }
LIMIT="${4:-20}"
[[ "${LIMIT}" =~ ^-?[0-9]+$ ]] || { printf "LIMIT is a number, not %s.\n" "${LIMIT}"; exit 2; }
FOLDERS="${5:-true}"
[[ "${FOLDERS}" =~ ^(true|false)$ ]] || { printf "FOLDERS is true or false, not %s.\n" "${FOLDERS}"; exit 2; }

# The one site of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
read -r FOUND SITE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s sites named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

SITE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${SITE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${SITE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the site %s (id %s).\n" "${NAME}" "${SITE_ID}"
    exit 1
fi
BODY=$(printf '%s' "${SITE_JSON}" | jq -c '{id, name, host: (.host // ""), port: (.port // ""), protocol, account}')

printf "Listing the %s of the site %s of %s...\n" "${FOLDER_TO_LIST}" "${NAME}" "${ACCOUNT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST \
  "${MAIN_URL}/operations?operation=listRemoteFolder&folderToList=${FOLDER_TO_LIST}&limit=${LIMIT}&includesFolderNamesInResult=${FOLDERS}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf '%s\n' "${RESPONSE}"
    exit 1
fi
printf '%s' "${RESPONSE}" | jq -r '"  connection:  \(.connectionStatus)", "  folder:      \(.remoteFolder)",
  (if (.errorDetails // "") != "" then "  error:       \(.errorDetails)" else empty end),
  "  entries:     \(.resultSet.returnCount) of \(.resultSet.totalCount)",
  ((.result // [])[] | "    \(.fileName)  \(.fileSize)  \(.filePermissions)  \(.lastModifiedTime)")'
printf '%s' "${RESPONSE}" | jq -e '.connectionStatus == "success" and ((.errorDetails // "") == "")' >/dev/null
