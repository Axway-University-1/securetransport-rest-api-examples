#!/bin/bash
# ==============================================================================
# Script Name: 02.transferProfiles_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a transfer profile using the `/transferProfiles` endpoint.
# A profile belongs to an account and tells a PeSIT transfer which file to send, what to call
# the file it receives, and how the file is labelled. It demonstrates:
# - A profile with advancedSettings, which is how a profile says what happens to the content of a file: the
#   sending side (callerTranscoding) and the receiving side (receiverTranscoding) each get a `type`, binary, ascii
#   or ebcdic. The plain fields (transferMode, recordFormat...) stay as they are and are not used while the advanced
#   settings are enabled. The word `basic` makes a profile with the plain fields only (the smallest body the server
#   accepts: name, account, fileLabelOption and one mapping)
# - Reading the new profile's address from the Location header
#
# Usage:
# ./02.transferProfiles_POST.sh [ACCOUNT [NAME [SEND_MAPPING [RECEIVE_MAPPING [TRANSCODING]]]]]
#
#   ACCOUNT          the account the profile is for (default john; it needs a PeSIT site)
#   NAME             the profile's name (default example_profile)
#   SEND_MAPPING     the file to send (default /example_file.txt)
#   RECEIVE_MAPPING  what to call a file received; may not contain * or ? (default: none)
#   TRANSCODING      binary (default), ascii or ebcdic: the advancedSettings type of both sides; or basic, for a
#                    profile with the plain fields only (no advancedSettings)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Transfer profiles are a PeSIT thing. Confirmed directly: a profile for an account that has no PeSIT transfer site
#   is refused, 400 "Account does not contain any PeSIT transfer sites."; an account that does not exist is 404.
# - Run 07.transferProfiles_id_DELETE.sh to remove what this creates.
# - Confirmed directly (PeSIT pulls on the lab, the bytes read on the wire and in the stored file; check 59): with
#   `binary` on both sides a file travels and is stored byte for byte. With `ascii` the sender cuts a file into records at
#   each LF (a CR before it goes too) and the receiver puts an LF after each record: CRLF becomes LF, a final newline is
#   added when there was none, and a line longer than 2048 bytes makes the transfer fail ("Record length too long").
#   `ebcdic` sends the bytes as they are and announces them as EBCDIC, ends records at 0x15, and a receiving `ebcdic`
#   converts ASCII to EBCDIC (IBM1047) only when the sender says the data is ASCII. The server reads the profile back with
#   the read-only parts filled in (localDataCode, networkDataCode, outputRecordFormat VARIABLE, outputRecordLength 2048,
#   a paddingCharacter of \u0020 for ascii and \u0040 for ebcdic, lineEndingFormat DEFAULT). `type` is case sensitive and
#   an unknown one is 400. While `advancedSettings.enabled` is true they win over `transferMode`; set it false and the
#   plain fields are in force again, whatever the advanced settings hold. The other options (record format and length,
#   padding character, line ending, the conversions between character sets) are changed with 05 and 06 and tried in check 59.
# - Confirmed directly: a success is 201 with the new profile's address in `Location` and no body. `fileLabelOption`
#   (DONT_SEND, SEND_FILENAME or SEND_FILENAME_AND_PATH) is required though the reference's example omits it, and so
#   are `name` and `account`; at least one of `sendMapping` and `receiveMapping` must be set (400 otherwise). Everything
#   else has a default: not the default profile, BINARY, Variable records of 2048, no acknowledgment, no padding strip,
#   `receiveMapping` an empty string. A second profile with the same account and name is 400 "The transfer profile
#   cannot have the same account and name.", but names are case sensitive (`p1` and `P1` coexist) and the same name on
#   another account is fine. A name with a space is accepted; a name of 300 characters is a 403 "unable to comply".
#   The server stores a `/` in front of both mappings: `in.txt` reads back `/in.txt`, and a relative or an absolute
#   `receiveMapping` lands the file in the same place (the pull's destination directory). `sendMapping` is 250 characters at
#   most, `recordLength` 1 to 32767. `receiveMapping` may not contain `*` or `?` (400); `sendMapping` may (`/*`).
#   `default` true turns the account's previous default off. Deleting the account deletes its profiles.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/transferProfiles"
ACCOUNT="${1:-john}"
NAME="${2:-example_profile}"
SEND_MAPPING="${3:-/example_file.txt}"
RECEIVE_MAPPING="$4"
TRANSCODING="${5:-binary}"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${NAME// /}" ]; then
    printf "NAME must not be empty.\n"
    exit 2
fi
if [[ "${RECEIVE_MAPPING}" == *[\*\?]* ]]; then
    printf "RECEIVE_MAPPING may not contain * or ?: %s\n" "${RECEIVE_MAPPING}"
    exit 2
fi
if [ "${#SEND_MAPPING}" -gt 250 ]; then
    printf "SEND_MAPPING is 250 characters at most.\n"
    exit 2
fi
case "${TRANSCODING}" in
    binary|ascii|ebcdic|basic) ;;
    *) printf "TRANSCODING is binary, ascii, ebcdic or basic, not %s.\n" "${TRANSCODING}"; exit 2 ;;
esac

# receiveMapping is left out when there is none; advancedSettings when the profile is basic
BODY=$(jq -cn --arg name "${NAME}" --arg account "${ACCOUNT}" --arg send "${SEND_MAPPING}" --arg receive "${RECEIVE_MAPPING}" --arg type "${TRANSCODING}" \
  '{name: $name, account: $account, sendMapping: $send, fileLabelOption: "DONT_SEND"}
   + (if $receive != "" then {receiveMapping: $receive} else {} end)
   + (if $type != "basic" then {advancedSettings: {enabled: true, callerTranscoding: {type: $type}, receiverTranscoding: {type: $type}}} else {} end)')

printf "Creating the transfer profile %s for %s (%s)...\n" "${NAME}" "${ACCOUNT}" "${TRANSCODING}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
