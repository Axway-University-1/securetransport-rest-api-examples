#!/bin/bash
# ==============================================================================
# Script Name: 07.transferSites_downloadPattern.sh
# Author: Plamen Milenkov
# Created: 2025-09-29
# Location: Sofia
# ==============================================================================
# Description:
# This script demonstrates a transfer site's own downloadPattern field, using
# both pattern languages the EL documentation's pluggable-transfer-site
# "Download pattern examples" table shows: glob and regexp. Unlike a route
# step's fileFilterExpression (03 and 04 in this folder), a site names its
# pattern type field downloadPatternType, and its accepted values are lower
# case.
#
#   glob:  *.xml                     files ending in .xml
#   glob:  *.[0-9]                   files with a single digit extension
#   regex: .*\.(xml|txt)             files ending in .xml or .txt
#
# APIs used - /myself ( ST login and logout )
#             /sites ( POST, GET, DELETE )
#
# Usage:
# ./07.transferSites_downloadPattern.sh
#
# Risk: write
#
# Notes:
# - Confirmed directly against a real server: downloadPatternType is only
#   recognised on some site types (ssh here) - the same field name on an
#   http site is rejected outright as "Unsupported parameter", a real,
#   confirmed per-type schema difference, not a bug in this script.
# - downloadPatternType only accepts lower case values, and confirmed
#   directly to be "glob" or "regex" - not "regexp", which is what a route
#   step's fileFilterExpressionType calls the same concept (GLOB, REGEXP,
#   TEXT_FILES - all upper case there, too). Two fields for the same idea,
#   in two different case conventions, with two different spellings for the
#   regex option - confirmed directly rather than assumed, since guessing
#   either the case or the spelling from the other field would have been
#   wrong.
# - This site is attached to the account "john", which must already exist,
#   the same assumption 01.sites_POST.sh in 06.TransferSites makes.
# ==============================================================================

SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/sites"

create_site() {
    local suffix="$1"
    local pattern="$2"
    local pattern_type="$3"
    local name="ZZTEST_EL_dlpattern_${suffix}"

    printf "\nCreating %s with downloadPattern: %s (%s)\n" "${name}" "${pattern}" "${pattern_type}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
    -d "{
      \"name\": \"${name}\",
      \"type\": \"ssh\",
      \"protocol\": \"ssh\",
      \"account\": \"john\",
      \"host\": \"${ST_SERVER}\",
      \"port\": \"22\",
      \"downloadFolder\": \"/tmp\",
      \"downloadPattern\": \"${pattern}\",
      \"downloadPatternType\": \"${pattern_type}\",
      \"uploadFolder\": \"/\",
      \"userName\": \"john\",
      \"usePassword\": true,
      \"password\": \"placeholder\"
    }"
}

create_site "anyXml"      '*.xml'          'glob'
create_site "singleDigit" '*.[0-9]'        'glob'
create_site "xmlOrTxt"    '.*\\.(xml|txt)' 'regex'

printf "\n\nReading all three back, and cleaning each up...\n"
for SUFFIX in anyXml singleDigit xmlOrTxt; do
    NAME="ZZTEST_EL_dlpattern_${SUFFIX}"
    printf "\n%s:\n" "${NAME}"
    curl -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=name,downloadPattern,downloadPatternType" -H "accept: application/json" -H "${REFERER_HEADER}"

    ID=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?name=${NAME}&fields=id" -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r '.result[0].id // empty')
    if [ -n "${ID}" ]; then
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/${ID}" -H "accept: application/json" -H "${REFERER_HEADER}"
        printf "\ndeleted %s (%s)\n" "${NAME}" "${ID}"
    fi
done
