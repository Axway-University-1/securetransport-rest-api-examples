#!/bin/bash
# ==============================================================================
# Script Name: 01.mailTemplates_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the mail templates using the `/mailTemplates` endpoint: the
# XHTML files SecureTransport builds its notification e-mails from.
# It demonstrates:
# - Counting them
# - Listing them, one line each with the description
# - Searching by name, and by description (both exact)
#
# Usage:
# ./01.mailTemplates_GET.sh [NAME [DESCRIPTION]]
#
#   NAME         a template's exact name, e.g. AdhocDefault.xhtml (optional)
#   DESCRIPTION  an exact description (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is {resultSet, result}; each entry has name, description
#   (null when there is none) and metadata.links.self. The list is sorted by name, ignoring case.
# - Confirmed directly: name= and description= are exact and case sensitive, with no * wildcard
#   (name=Account* finds nothing), and resultSet.totalCount still counts every template.
# - Confirmed directly: limit=-1 answers 400 "The limit should be a positive number or 0."; limit=0
#   gives the default page size.
# - The server ships templates of its own, for its notification e-mails: do not change them without
#   keeping a copy (04.mailTemplates_name_GET.sh saves one).
# - Requires `jq`, which prints one template per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="$1"
DESCRIPTION="$2"
LINE='"  \(.name)  \(.description // "-")"'

printf "Mail templates: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nAll of them: name, description:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=100" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${NAME}" ]; then
    printf "\nNamed %s:\n" "${NAME}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi

if [ -n "${DESCRIPTION}" ]; then
    printf "\nDescribed as %s:\n" "${DESCRIPTION}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "description=${DESCRIPTION}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi
