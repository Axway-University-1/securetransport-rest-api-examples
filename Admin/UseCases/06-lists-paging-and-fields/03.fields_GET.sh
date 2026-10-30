#!/bin/bash
# ==============================================================================
# Script Name: 03.fields_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Lists, step 3: fewer fields. fields=name,contact narrows every entry to the fields you name (the type of the object is always kept). The script shows an entry with and without fields=, a field that does not exist (400),
# and the one field of /servers that is in every answer and cannot be asked for: protocol.
#
# Usage:
# ./03.fields_GET.sh [RESOURCE] [FIELDS]
#
#   RESOURCE  the list to read (default accounts)
#   FIELDS    the fields to ask for, separated by commas (default name)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/01.accounts_GET.sh (its fields parameter).
# - A name inside an object is written with a dot: contact.email. Naming the object (contact) gives all its fields.
# - Refusals are the expected answer here: a field that does not exist is 400 "Field nosuch does not exist.", and so is protocol on /servers (and type on /sites), although the answer holds them. If the server answers 200 to either, the script says so and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.fields_GET.sh [RESOURCE] [FIELDS]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: RESOURCE and FIELDS.\n%s\n" "$#" "${USAGE}"; exit 2; fi
RESOURCE="${1:-accounts}"
FIELDS="${2:-name}"
uc_check_resource "${RESOURCE}" "${USAGE}"
if [[ ! "${FIELDS}" =~ ^[A-Za-z][A-Za-z0-9._]*(,[A-Za-z][A-Za-z0-9._]*)*$ ]]; then
    printf "FIELDS is '%s': it is a list of field names separated by commas, such as name,contact.email.\n%s\n" "${FIELDS}" "${USAGE}"
    exit 2
fi
st_session

uc_list "${RESOURCE}" "limit=1"
echo "GET /${RESOURCE}?limit=1: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
if [ "$(printf '%s' "${LIST_BODY}" | jq -r '.result | length')" = "0" ]; then echo "The list /${RESOURCE} is empty: there is no entry to look at."; exit 1; fi
echo "  one entry has $(printf '%s' "${LIST_BODY}" | jq -r '.result[0] | keys | length') fields: $(printf '%s' "${LIST_BODY}" | jq -r '.result[0] | keys | join(", ")')"

uc_list "${RESOURCE}" "limit=1" "fields=${FIELDS}"
echo "GET /${RESOURCE}?limit=1&fields=${FIELDS}: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
echo "  now it has $(printf '%s' "${LIST_BODY}" | jq -r '.result[0] | keys | length') fields: $(printf '%s' "${LIST_BODY}" | jq -r '.result[0] | keys | join(", ")')"
echo "  the type of the object, when there is one, is there although it was not asked for."

uc_list "${RESOURCE}" "limit=1" "fields=nosuch"
echo "A field that does not exist (fields=nosuch): HTTP ${LIST_CODE}"
if [ "${LIST_CODE}" != "400" ]; then
    echo "The server was expected to refuse it with 400."
    exit 1
fi
echo "  $(uc_why)"

uc_list "servers" "limit=1" "fields=serverName"
echo "GET /servers?limit=1&fields=serverName: HTTP ${LIST_CODE}"
[ "${LIST_CODE}" = "200" ] || { uc_why; exit 1; }
echo "  the entry is $(printf '%s' "${LIST_BODY}" | jq -c '.result[0]'): protocol is in it, though only serverName was asked for."
uc_list "servers" "limit=1" "fields=protocol"
echo "GET /servers?limit=1&fields=protocol: HTTP ${LIST_CODE}"
if [ "${LIST_CODE}" != "400" ]; then
    echo "The server was expected to refuse protocol with 400."
    exit 1
fi
echo "  $(uc_why)"
echo "The field that tells the kind of an object cannot be named: leave it out of fields= and read it from the answer."
