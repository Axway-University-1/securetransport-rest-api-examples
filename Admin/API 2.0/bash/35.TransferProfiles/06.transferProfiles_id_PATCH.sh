#!/bin/bash
# ==============================================================================
# Script Name: 06.transferProfiles_id_PATCH.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script changes one property of a transfer profile, using the `/transferProfiles/{id}`
# endpoint with PATCH: a JSON Patch document that replaces the record length of the receiving side
# (advancedSettings.receiverTranscoding.outputRecordLength), of the sending side, or the plain recordLength. Unlike PUT
# (05.transferProfiles_id_PUT.sh), it sends only what changes.
#
# Usage:
# ./06.transferProfiles_id_PATCH.sh ACCOUNT NAME [RECORD_LENGTH [SIDE]]
#
#   ACCOUNT        the account the profile belongs to
#   NAME           the profile (it must be the only one with that name)
#   RECORD_LENGTH  the new record length, 1 to 32767 (default 1024)
#   SIDE           receiver (default), caller or basic: the receiving side's advanced setting, the sending side's, or the
#                  plain recordLength. The advanced sides need advancedSettings enabled and a type that has a record length
#                  (ascii, ebcdic, ascii_predefined, ...: not binary)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It prints the record length before, to put it back with. When the profile has none at that place (advanced settings off, or
#   a binary side) it says so and sends nothing: confirmed directly, the server answers 204 to a patch of a field that the
#   side's type does not have, and changes nothing. A PATCH cannot change a side's `type` (400 "Patch operation on read only or
#   discriminator fields is not permitted."): PUT the profile again for that (05). The record length of a sender is what the
#   receiver compares each record with: a record longer than it fails the transfer ("Record length too long"), check 59.
# - Confirmed directly: a success answers 204, with no body, and an empty patch is 204 too. `replace` and `add` of the
#   scalar fields work (`/sendMapping`, `/receiveMapping`, `/recordLength`, `/default`, `/name`); `add` to
#   `/additionalAttributes/userVars.<name>` works, the key must start with `userVars.` and the value may not be blank
#   (400). `replace` of `/account` is 204 and changes nothing; of `/id` 400. A path that does not exist is 400
#   `Missing field "nope"`, a value out of range or not in the enum is 400 with the reason ("recordLength must be greater
#   than or equal to 1"), and a patch that would leave no `sendMapping` and no `receiveMapping` is refused, 400. An unknown
#   id is a JSON 404. `default` true on a profile turns the account's previous default off.
# - Per the reference, the plain `recordLength` is used only while `advancedSettings.enabled` is false; the advanced lengths
#   only while it is true (confirmed on transfers in check 59).
# - Requires `jq`, which reads the id and builds the patch.
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
[ -n "${ACCOUNT}" ] && [ -n "${NAME}" ] || { printf "Usage: ./06.transferProfiles_id_PATCH.sh ACCOUNT NAME [RECORD_LENGTH]\n"; exit 2; }
RECORD_LENGTH="${3:-1024}"
SIDE="${4:-receiver}"
case "${SIDE}" in
    receiver) JSON_PATH="/advancedSettings/receiverTranscoding/outputRecordLength"
              BEFORE_FILTER='if .advancedSettings.enabled and (.advancedSettings.receiverTranscoding.type != "binary") then .advancedSettings.receiverTranscoding.outputRecordLength else empty end' ;;
    caller)   JSON_PATH="/advancedSettings/callerTranscoding/outputRecordLength"
              BEFORE_FILTER='if .advancedSettings.enabled and (.advancedSettings.callerTranscoding.type != "binary") then .advancedSettings.callerTranscoding.outputRecordLength else empty end' ;;
    basic)    JSON_PATH="/recordLength"
              BEFORE_FILTER='.recordLength' ;;
    *) printf "SIDE is receiver, caller or basic, not %s.\n" "${SIDE}"; exit 2 ;;
esac
[[ "${RECORD_LENGTH}" =~ ^[0-9]+$ ]] && [ "${RECORD_LENGTH}" -ge 1 ] && [ "${RECORD_LENGTH}" -le 32767 ] || { printf "RECORD_LENGTH is a number from 1 to 32767, not %s.\n" "${RECORD_LENGTH}"; exit 2; }

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
BEFORE=$(printf '%s' "${PROFILE_JSON}" | jq -r "${BEFORE_FILTER}")
if [ -z "${BEFORE}" ]; then
    printf "The transfer profile %s has no record length for %s: its advanced settings are off or that side is binary. Nothing sent.\n" "${NAME}" "${SIDE}"
    exit 1
fi
printf "The record length of %s (%s) is now %s.\n" "${NAME}" "${SIDE}" "${BEFORE}"
BODY=$(jq -cn --argjson value "${RECORD_LENGTH}" --arg path "${JSON_PATH}" '[{op: "replace", path: $path, value: $value}]')

printf "Setting it to %s...\n" "${RECORD_LENGTH}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${MAIN_URL}/${PROFILE_ID}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
