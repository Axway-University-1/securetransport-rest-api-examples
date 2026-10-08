#!/bin/bash
# ==============================================================================
# Script Name: 05.transferProfiles_id_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a transfer profile, using the `/transferProfiles/{id}` endpoint with PUT:
# it reads the profile, changes the line ending of the receiving side (advancedSettings.receiverTranscoding.lineEndingFormat)
# and, when asked, the file it sends (sendMapping, a plain field), and sends the whole profile back.
#
# Usage:
# ./05.transferProfiles_id_PUT.sh ACCOUNT NAME [LINE_ENDING [SEND_MAPPING]]
#
#   ACCOUNT       the account the profile belongs to
#   NAME          the profile (it must be the only one with that name)
#   LINE_ENDING   DEFAULT, UNIX or WINDOWS (default WINDOWS): what a receiving ascii, ebcdic or predefined side ends each record
#                 with. - leaves it alone. The profile needs advancedSettings enabled and such a receiving side (02 ... ascii)
#   SEND_MAPPING  the new file to send, as well (250 characters at most). Without LINE_ENDING use - : 05 ... NAME - /new.txt
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the values before, to put them back with. A profile whose advanced settings are off, or whose receiving side is
#   binary, has no line ending to change: the script says so and sends nothing (the server would answer 204 and ignore it,
#   confirmed directly). `type` cannot be changed by PATCH (400, a discriminator) but a PUT with another type works, and the
#   fields that belong to the old type are dropped.
# - PUT replaces the whole profile, and the body needs the profile's `id`. Confirmed directly: a body without it is 400
#   "id to load is required for loading", and a hand-built fragment WITH the id (name, account, sendMapping, fileLabelOption)
#   answers 204 and silently resets everything it leaves out: transferMode, recordFormat, recordLength, multiSelect,
#   the acknowledgment and padding flags, the additional attributes. That is why the profile is read first and sent back with
#   one field changed. `metadata`, the read-only link, is left out.
# - Confirmed directly: a success answers 204, with no body. `default` in the body is applied (true turns the account's
#   previous default off). `account` in the body is accepted and ignored; `name` renames the profile; a name the account
#   already has is a 403 "unable to comply" (not 400). An unknown id is a JSON 404, and a body without `fileLabelOption` 400.
# - Requires `jq`, which reads the id and edits the profile.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
ACCOUNT="$1"
NAME="$2"
[ -n "${ACCOUNT}" ] && [ -n "${NAME}" ] || { printf "Usage: ./05.transferProfiles_id_PUT.sh ACCOUNT NAME [SEND_MAPPING]\n"; exit 2; }
LINE_ENDING="${3:-WINDOWS}"
SEND_MAPPING="$4"
case "${LINE_ENDING}" in
    DEFAULT|UNIX|WINDOWS|-) ;;
    *) printf "LINE_ENDING is DEFAULT, UNIX, WINDOWS or -, not %s.\n" "${LINE_ENDING}"; exit 2 ;;
esac
if [ "${LINE_ENDING}" = "-" ] && [ -z "${SEND_MAPPING}" ]; then
    printf "Nothing to change: give a LINE_ENDING or a SEND_MAPPING.\n"
    exit 2
fi
if [ "${#SEND_MAPPING}" -gt 250 ]; then
    printf "SEND_MAPPING is 250 characters at most.\n"
    exit 2
fi

# The one profile of that account with that name: "1 <id>", or how many there are.
# The name filter ignores case and takes a * wildcard, so the exact name is
# picked out of what comes back.
read -r FOUND PROFILE_ID < <(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
  --data-urlencode "account=${ACCOUNT}" --data-urlencode "name=${NAME}" --data-urlencode "fields=id,name" \
  -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r --arg name "${NAME}" '[(.result // [])[] | select(.name == $name)] | if length == 1 then "1 \(.[0].id)" else "\(length)" end')
if [ "${FOUND}" != "1" ]; then
    printf "Found %s transfer profiles named %s on the account %s; this script acts on exactly one.\n" "${FOUND:-0}" "${NAME}" "${ACCOUNT}"
    exit 1
fi

PROFILE_JSON=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${PROFILE_ID}" -H "accept: application/json" -H "${REFERER_HEADER}")
if ! printf '%s' "${PROFILE_JSON}" | jq -e '.id' >/dev/null 2>&1; then
    printf "Could not read the transfer profile %s (id %s).\n" "${NAME}" "${PROFILE_ID}"
    exit 1
fi
if [ "${LINE_ENDING}" != "-" ]; then
    BEFORE=$(printf '%s' "${PROFILE_JSON}" | jq -r 'if .advancedSettings.enabled and (.advancedSettings.receiverTranscoding.type | IN("ascii", "ebcdic", "predefined", "custom_table")) then .advancedSettings.receiverTranscoding.lineEndingFormat else empty end')
    if [ -z "${BEFORE}" ]; then
        printf "The transfer profile %s has no receiving line ending: its advanced settings are off or its receiving side is binary. Nothing sent.\n" "${NAME}"
        exit 1
    fi
    printf "The lineEndingFormat of %s is now %s.\n" "${NAME}" "${BEFORE}"
fi
if [ -n "${SEND_MAPPING}" ]; then
    printf "The sendMapping of %s is now %s.\n" "${NAME}" "$(printf '%s' "${PROFILE_JSON}" | jq -r '.sendMapping')"
fi
BODY=$(printf '%s' "${PROFILE_JSON}" | jq -c --arg ending "${LINE_ENDING}" --arg send "${SEND_MAPPING}" \
  '(if $ending != "-" then .advancedSettings.receiverTranscoding.lineEndingFormat = $ending else . end)
   | (if $send != "" then .sendMapping = $send else . end) | del(.metadata)')

printf "Changing it...\n"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${PROFILE_ID}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
