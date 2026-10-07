#!/bin/bash
# ==============================================================================
# Script Name: 06.mailTemplates_name_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes a mail template, using the `/mailTemplates/{name}` endpoint.
#
# Usage:
# ./06.mailTemplates_name_DELETE.sh NAME
#
#   NAME  the template. There is no default: name the one to delete.
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is 204; a name that does not exist answers 404 "Mail Template ...
#   not found." The name is case sensitive.
# - NOT run on the lab against one of the server's own templates (AdhocDefault.xhtml and the
#   like): the notification e-mails are built from them. Save a copy first with
#   04.mailTemplates_name_GET.sh.
# - Requires `jq`, which URL-encodes the name and prints the reason.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="$1"
[ -n "${NAME}" ] || { printf "Usage: ./06.mailTemplates_name_DELETE.sh NAME\n"; exit 2; }

if [ -z "${NAME// /}" ] || [[ "${NAME}" == */* ]] || [[ "${NAME}" == *\\* ]]; then
    printf "NAME must not be blank, and must not hold a / or a \\: %s\n" "${NAME}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

printf "Deleting the mail template %s...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s' "${RESPONSE}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
