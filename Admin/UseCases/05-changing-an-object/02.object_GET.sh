#!/bin/bash
# ==============================================================================
# Script Name: 02.object_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 2: read first. GETs the account and the route, keeps a copy of each (state.local.account.json and state.local.route.json), and shows the fields the next steps change with their JSON type. The type
# of the value is what decides how to write the patch.
#
# Usage:
# ./02.object_GET.sh [NAME]
#
#   NAME  the account to read; the route is NAME_route (default example_chg)
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/04.accounts_name_GET.sh and 09.CompositeRoutes/06.routes_GET.sh.
# - Read the object before every change, and keep the copy: it is what you compare with afterwards, and what a PUT sends back.
# - Look at the types. `uid` is a string, although it looks like a number: a number sent to it is stored as text (see 04).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.object_GET.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account
uc_need route

code=$(curl -k -s -o "${ACCOUNT_COPY}" -w "%{http_code}" -b "${JAR}" -X GET "${ACCOUNT_URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "GET account: HTTP ${code}"
[ "${code}" = "200" ] || { echo "The account could not be read."; rm -f "${ACCOUNT_COPY}"; exit 1; }
code=$(curl -k -s -o "${ROUTE_COPY}" -w "%{http_code}" -b "${JAR}" -X GET "${ROUTE_URL}" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "GET route: HTTP ${code}"
[ "${code}" = "200" ] || { echo "The route could not be read."; rm -f "${ROUTE_COPY}"; exit 1; }
echo "Copies kept in $(basename "${ACCOUNT_COPY}") and $(basename "${ROUTE_COPY}")."

echo
echo "The account ${NAME}: field, JSON type, value (the steps 03 to 08 change these)"
jq -r '[["notes", .notes], ["contact.email", .contact.email], ["contact.phone", .contact.phone], ["user.failedAuthMaximum", .user.failedAuthMaximum], ["uid", .uid],
        ["bandwidthLimits.inboundLimit", .bandwidthLimits.inboundLimit], ["transfersWebServiceAllowed", .transfersWebServiceAllowed], ["disabled", .disabled],
        ["contact", .contact], ["bandwidthLimits", .bandwidthLimits]][] | "  \(.[0] + "                              " | .[0:30]) \(.[1] | type | . + "       " | .[0:8]) \(.[1] | tojson)"' "${ACCOUNT_COPY}"
echo
echo "The route ${ROUTE_NAME}: its steps are a list. A path into it is a position, counted from 0."
jq -r '"  description                    \(.description | type | . + "       " | .[0:8]) \(.description | tojson)",
       "  steps                          \(.steps | type | . + "       " | .[0:8]) \((.steps // []) | length) steps",
       ((.steps // []) | to_entries[] | "    position \(.key): fileFilterExpression \(.value.fileFilterExpression), status \(.value.status), id \(.value.id)")' "${ROUTE_COPY}"
