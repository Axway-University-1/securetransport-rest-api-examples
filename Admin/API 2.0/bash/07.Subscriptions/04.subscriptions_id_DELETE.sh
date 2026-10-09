#!/bin/bash
# ==============================================================================
# Script Name: 04.subscriptions_id_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-05
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes subscriptions using the `/subscriptions/{id}` endpoint,
# and then the application they used. It demonstrates:
# - Looking up the id of a subscription by account, application and folder
# - Deleting the subscription by that id
# - Deleting the application, once nothing subscribes to it
# - Printing the HTTP code of each delete, and exiting 1 when the server refuses one
#
# Usage:
# ./04.subscriptions_id_DELETE.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - This cleans up what 02.subscriptions_POST.sh and
#   03.subscriptions_POST_triggerfile.sh create for the account "john": the
#   subscriptions on /inbox and /inbox-trigger, and the application
#   AdvancedRoutingApplication. Only ever point it at what you created.
# - Delete a composite route that is linked to a subscription first. See
#   09.CompositeRoutes/07.routes_id_DELETE.sh.
# - The subscription is looked up with the exact account and application (both filters are exact) and the folder is compared on what
#   comes back; a subscription that is not there is reported and skipped, and two that match are not deleted (exit 1). A plain DELETE
#   leaves the folder in the account's home folder: 07.Subscriptions/13 shows `purge=true`, which removes it.
# - The application that is not there (404) is reported and skipped. One that still has a subscription is refused, 400 "has active
#   subscriptions", and the script exits 1.
# - Requires `jq`, which picks the subscription out of the response.
# - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Subscription with id X not found or not accessible.",
#   and an application that is not there is a JSON 404 too, "Application with name X not found or not accessible.".
# - Exit codes: 0 when everything was deleted or was not there, 1 when the server refuses a lookup or a delete, or two subscriptions
#   match. It takes no argument.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./04.subscriptions_id_DELETE.sh\n"
    exit 2
fi

ACCOUNT="${ST_EXAMPLE_ACCOUNT:-john}"
APPLICATION="AdvancedRoutingApplication"
FAILED=0

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

for FOLDER in "/inbox" "/inbox-trigger"; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}/subscriptions" \
      --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not look up the subscriptions of '%s': HTTP %s\n" "${ACCOUNT}" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        FAILED=1
        continue
    fi
    IDS=$(printf '%s' "${RESPONSE}" | jq -r --arg folder "${FOLDER}" --arg application "${APPLICATION}" \
      '[(.result // [])[] | select(.folder == $folder and .application == $application) | .id][]')
    COUNT=$(printf '%s' "${IDS}" | grep -c .)

    if [ "${COUNT}" -eq 0 ]; then
        printf "The account '%s' has no subscription on '%s'.\n" "${ACCOUNT}" "${FOLDER}"
        continue
    fi
    if [ "${COUNT}" -gt 1 ]; then
        printf "The account '%s' has %s subscriptions on '%s' and '%s'; none deleted.\n" "${ACCOUNT}" "${COUNT}" "${FOLDER}" "${APPLICATION}"
        FAILED=1
        continue
    fi

    SUBSCRIPTION_ID="${IDS}"
    printf "Deleting the subscription on '%s' (%s)...\n" "${FOLDER}" "${SUBSCRIPTION_ID}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/subscriptions/$(jq -rn --arg n "${SUBSCRIPTION_ID}" '$n|@uri')" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        FAILED=1
        continue
    fi
    printf "Deleted the subscription on '%s'.\n" "${FOLDER}"
done

printf "Deleting the application '%s'...\n" "${APPLICATION}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/applications/$(jq -rn --arg n "${APPLICATION}" '$n|@uri')" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" = "204" ]; then
    printf "Deleted the application '%s'.\n" "${APPLICATION}"
elif [ "${HTTP_CODE}" = "404" ]; then
    printf "There is no application '%s'.\n" "${APPLICATION}"
else
    show_error "${RESPONSE}"
    FAILED=1
fi
exit "${FAILED}"
