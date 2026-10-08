#!/bin/bash
# ==============================================================================
# Script Name: 02.subscriptions_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script subscribes an account's folder to an Advanced Routing application,
# using the `/applications` and `/subscriptions` endpoints. It demonstrates:
# - Creating the Advanced Routing application the subscription needs
# - Creating the subscription, with the pull site as its PARTNER-IN transfer
#   configuration, so that what the site pulls lands in the folder
# - Reading the id of the new subscription from the Location header
# - The HTTP code of each call, from curl itself (-w), not from the head of a headers file
#
# Usage:
# ./02.subscriptions_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The account "john" and its site SSH_PULL must already exist. Run
#   06.TransferSites/02.sites_POST_ssh.sh first.
# - If the application already exists, its POST is refused (400 "An application with
#   this name already exists.", not a 409) and the subscription is created against
#   the existing one.
# - A route only runs on what arrives in the folder once a composite route is
#   linked to the subscription. See
#   09.CompositeRoutes/05.routes_POST_composite_subscription.sh.
# - 04.subscriptions_id_DELETE.sh removes the subscription and the application again.
# - Requires `jq`, which builds the request bodies.
# - The status is read with `curl -w "\n%{http_code}"`. The older script took it from the first line of the headers file, which is the
#   line of an interim `HTTP/1.1 100 Continue` or of a redirect when there is one, and so printed the wrong code.
# - Confirmed directly: the application is 201 with no body; one that exists is 400 "An application with this name already exists." (the
#   script goes on with the one that is there, and exits 1 for any other refusal). The subscription is 201 with the new id at the end of `Location`.
# - Exit codes: 0 when the subscription was created (201), 1 when the server refuses the application (other than because it exists) or the
#   subscription. It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./02.subscriptions_POST.sh\n"
    exit 2
fi

ACCOUNT="john"
APPLICATION="AdvancedRoutingApplication"
FOLDER="/inbox"
PULL_SITE="SSH_PULL"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

BODY=$(jq -cn --arg name "${APPLICATION}" \
  '{type: "AdvancedRouting", name: $name, notes: "Created by 07.Subscriptions"}')

printf "Creating the application '%s'...\n" "${APPLICATION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/applications" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
  -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    show_error "${RESPONSE}"
    if { [ "${HTTP_CODE}" = "400" ] || [ "${HTTP_CODE}" = "409" ]; } && printf '%s' "${RESPONSE}" | grep -q "already exists"; then
        printf "The application exists already: the subscription goes on it.\n"
    else
        exit 1
    fi
fi

BODY=$(jq -cn --arg account "${ACCOUNT}" --arg application "${APPLICATION}" \
  --arg folder "${FOLDER}" --arg site "${PULL_SITE}" \
  '{type: "AdvancedRouting", account: $account, application: $application, folder: $folder,
    transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site}]}')

printf "Subscribing the folder '%s' of '%s' to '%s'...\n" "${FOLDER}" "${ACCOUNT}" "${APPLICATION}"
RESPONSE=$(curl -s -D "${HEADERS_FILE}" -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}/subscriptions" \
  -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    show_error "${RESPONSE}"
    exit 1
fi
LOCATION=$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | tail -n 1)
if [ -n "${LOCATION}" ]; then
    printf "New subscription ID: %s\n" "${LOCATION##*/}"
fi
