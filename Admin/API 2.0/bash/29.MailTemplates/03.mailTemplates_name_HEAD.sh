#!/bin/bash
# ==============================================================================
# Script Name: 03.mailTemplates_name_HEAD.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script checks whether a mail template exists, using the
# `/mailTemplates/{name}` endpoint with HEAD: 200 when it does, 404 when it
# does not.
#
# Usage:
# ./03.mailTemplates_name_HEAD.sh [NAME]
#
#   NAME  the template (default example_mail.xhtml, which 02.mailTemplates_POST.sh
#         creates)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the name is case sensitive (EXAMPLE_MAIL.xhtml is 404 where
#   example_mail.xhtml is 200), and the 404 has an HTML body, not JSON.
# - Requires `jq`, which URL-encodes the name.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="${1:-example_mail.xhtml}"

if [ -z "${NAME// /}" ] || [[ "${NAME}" == */* ]] || [[ "${NAME}" == *\\* ]]; then
    printf "NAME must not be blank, and must not hold a / or a \\: %s\n" "${NAME}"
    exit 2
fi
ENCODED=$(jq -rn --arg name "${NAME}" '$name | @uri')

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k -u "${ST_USER}:${ST_PASSWORD}" --head "${MAIN_URL}/${ENCODED}" \
  -H "accept: */*" -H "${REFERER_HEADER}")
if [ "${HTTP_CODE}" = "200" ]; then
    printf "The mail template %s exists.\n" "${NAME}"
else
    printf "The mail template %s does not exist (HTTP %s).\n" "${NAME}" "${HTTP_CODE}"
    exit 1
fi
