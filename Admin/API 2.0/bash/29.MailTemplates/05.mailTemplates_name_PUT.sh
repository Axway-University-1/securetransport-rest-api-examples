#!/bin/bash
# ==============================================================================
# Script Name: 05.mailTemplates_name_PUT.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script replaces a mail template, using the `/mailTemplates/{name}` endpoint
# with PUT: it uploads an XHTML file as a multipart form.
#
# Usage:
# ./05.mailTemplates_name_PUT.sh NAME FILE [DESCRIPTION]
#
#   NAME         the template to replace. There is no default: name the one to change.
#   FILE         the XHTML file to upload
#   DESCRIPTION  the new description (default: the one it has now; "" clears it)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: PUT on a name that does not exist CREATES the template and answers 204,
#   not the 404 the reference lists. The script looks the template up first, and stops if it is
#   not there, so a mistyped name does not leave a new template behind.
# - Confirmed directly: a PUT with no description sets it to null, so the script reads the current
#   one and sends it again; an empty description makes it an empty string.
# - Confirmed directly: as with POST, the uploaded file must be named *.xhtml (the script sends
#   it under NAME) and its content is not checked.
# - Keep a copy of a template of the server's before replacing it: 04.mailTemplates_name_GET.sh.
# - Requires `jq`, which URL-encodes the name and reads the description.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="$1"
FILE="$2"

if [ -z "${NAME// /}" ] || [[ "${NAME}" == */* ]] || [[ "${NAME}" == *\\* ]]; then
    printf "NAME must not be blank, and must not hold a / or a \\: %s\n" "${NAME}"
    exit 2
fi
if [ ! -f "${FILE}" ]; then
    printf "Usage: ./05.mailTemplates_name_PUT.sh NAME FILE [DESCRIPTION]\n"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

# PUT creates a template that does not exist, so look first
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "404" ]; then
    printf "There is no mail template %s to replace.\n" "${NAME}"
    exit 1
fi
if [ "$#" -ge 3 ]; then
    DESCRIPTION="$3"
else
    DESCRIPTION=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" --data-urlencode "fields=description" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].description // ""')
fi

printf "Replacing the mail template %s with %s...\n" "${NAME}" "${FILE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/${ENCODED}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -F "file=@${FILE};type=application/xhtml+xml;filename=${NAME}" --form-string "description=${DESCRIPTION}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
