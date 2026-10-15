#!/bin/bash
# ==============================================================================
# Script Name: 09.myself_addressBook_id_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script reads one address book entry by its id, using the
# `/myself/addressBook/{id}` endpoint.
#
# Usage:
# ./09.myself_addressBook_id_GET.sh [ID]
#
#   ID  the entry's id, as 08.myself_addressBook_GET.sh prints it (default:
#       the first entry of the address book)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It checks for an active session first and, if there is none, logs in with
#   01.Authenticate/01.myself_POST.sh and then carries on.
# - An id holds a ':' (confirmed directly, for example
#   8a05...0032:8a05...0002), so it is URL-encoded in the path.
# - Requires `jq`, which URL-encodes the id.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"
source "${SCRIPT_DIR}/../ensure_session.sh"
REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

ENTRY_ID="$1"
st_ensure_session

if [ -z "${ENTRY_ID}" ]; then
    ENTRY_ID=$(curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/myself/addressBook?limit=1" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.[0].id // empty')
    if [ -z "${ENTRY_ID}" ]; then
        printf "The address book is empty, so there is no entry to read.\n"
        exit 1
    fi
fi

ENCODED_ID=$(printf '%s' "${ENTRY_ID}" | jq -sRr '@uri')
printf "Reading the address book entry %s...\n" "${ENTRY_ID}"
curl -s -k -b "${COOKIE}" -X GET "${ST_URL}/myself/addressBook/${ENCODED_ID}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\nHTTP %{http_code}\n"
