#!/bin/bash
# ==============================================================================
# Script Name: 04.mailTemplates_name_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script reads a mail template, using the `/mailTemplates/{name}` endpoint: its
# description, and the XHTML file itself, saved to a local file.
#
# Usage:
# ./04.mailTemplates_name_GET.sh [NAME [OUTPUT]]
#
#   NAME    the template (default example_mail.xhtml)
#   OUTPUT  the file to write (default: NAME, in the current folder)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is the file itself, application/xhtml+xml, with a
#   Content-Disposition of attachment; there is no JSON form (an accept of application/json still
#   answers the XHTML). The description is only in the list, so the script asks for it there, by
#   exact name. An unknown name answers 404 with a JSON message.
# - Keep the file this saves before replacing one of the server's own templates with
#   05.mailTemplates_name_PUT.sh.
# - Requires `jq`, which URL-encodes the name and prints the description and the error.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="${1:-example_mail.xhtml}"
OUTPUT="${2:-${NAME}}"

if [ -z "${NAME// /}" ] || [[ "${NAME}" == */* ]] || [[ "${NAME}" == *\\* ]]; then
    printf "NAME must not be blank, and must not hold a / or a \\: %s\n" "${NAME}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Description: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" --data-urlencode "fields=description" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].description // "-"'

HTTP_CODE=$(curl -s -o "${OUTPUT}" -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/${ENCODED}" \
  -H "accept: application/xhtml+xml" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "Written to %s, %s bytes.\n" "${OUTPUT}" "$(wc -c < "${OUTPUT}" | tr -d ' ')"
else
    printf "HTTP %s\n" "${HTTP_CODE}"
    jq -r '.validationErrors[0] // .message // .' "${OUTPUT}" 2>/dev/null
    rm -f "${OUTPUT}"
    exit 1
fi
