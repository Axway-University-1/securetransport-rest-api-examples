#!/bin/bash
# ==============================================================================
# Script Name: 13.subscriptions_id_DELETE_types.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes the subscriptions that 12.subscriptions_POST_types.sh creates, and
# the applications they used, using the `/subscriptions/{id}` endpoint. It
# demonstrates:
# - Looking up the id of a subscription by account, application and folder
# - Deleting it with purge=true, which also removes the subscription's folder
# - Deleting the application, once nothing subscribes to it
#
# Usage:
# ./13.subscriptions_id_DELETE_types.sh [ACCOUNT]
#
#   ACCOUNT  the account that was subscribed (default john)
#
# Risk: write - deletes the subscriptions of 12 and, with purge=true, their folders
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It only touches the applications ExampleBasicApplication, ExampleHumanSystemApplication,
#   ExampleMBFTApplication and ExampleStandardRouterApplication and the subscriptions of the account
#   on them, on the folders /example_Basic, /example_HumanSystem, /example_MBFT and
#   /example_StandardRouter. Files in those folders are deleted with them.
# - Confirmed directly: `?purge=true` removes the folder of the subscription from the account's home
#   folder; without it the folder stays. The answer is 204 either way. The applications are deleted
#   after their subscription: an application with a subscription is 400 "has active subscriptions".
# - The status of each call is read with `curl -w`, and a delete the server refuses (a 4xx or 5xx) makes the exit code 1; the next ones are
#   still tried. A subscription or an application that is not there (404) is reported, not an error.
# - Requires `jq`, which picks the subscription out of the response.
# - Exit codes: 0 when everything was deleted or was not there, 1 when the server refuses a lookup or a delete, or two subscriptions match,
#   2 when the account is empty or there is more than one argument (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/subscriptions"
ACCOUNT="${1:-john}"
if [ "$#" -gt 1 ] || [ -z "${ACCOUNT}" ]; then
    printf "Usage: ./13.subscriptions_id_DELETE_types.sh [ACCOUNT]\n"
    exit 2
fi
FAILED=0

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

for TYPE in Basic HumanSystem MBFT StandardRouter; do
    APPLICATION="Example${TYPE}Application"
    FOLDER="/example_${TYPE}"

    # The one subscription of that account on that application and folder: "1 <id>",
    # or how many there are. The account and application filters are exact; the
    # application and the folder are compared again here, on what comes back.
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
      --data-urlencode "account=${ACCOUNT}" --data-urlencode "application=${APPLICATION}" --data-urlencode "fields=id,application,folder" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not look up the subscriptions of '%s' on '%s': HTTP %s\n" "${ACCOUNT}" "${APPLICATION}" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        FAILED=1
    else
        IDS=$(printf '%s' "${RESPONSE}" | jq -r --arg application "${APPLICATION}" --arg folder "${FOLDER}" \
          '[(.result // [])[] | select(.application == $application and .folder == $folder) | .id][]')
        FOUND=$(printf '%s' "${IDS}" | grep -c .)
        if [ "${FOUND}" = "1" ]; then
            printf "Deleting the subscription on '%s' (%s), and its folder...\n" "${FOLDER}" "${IDS}"
            RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/$(jq -rn --arg n "${IDS}" '$n|@uri')?purge=true" \
              -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
            HTTP_CODE="${RESPONSE##*$'\n'}"
            RESPONSE="${RESPONSE%$'\n'*}"
            printf "HTTP %s\n" "${HTTP_CODE}"
            if [ "${HTTP_CODE}" != "204" ]; then
                show_error "${RESPONSE}"
                FAILED=1
            fi
        else
            printf "Found %s subscriptions of the account %s on the application %s and the folder %s; none deleted.\n" "${FOUND}" "${ACCOUNT}" "${APPLICATION}" "${FOLDER}"
            [ "${FOUND}" = "0" ] || FAILED=1
        fi
    fi

    printf "Deleting the application '%s'...\n" "${APPLICATION}"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/applications/$(jq -rn --arg n "${APPLICATION}" '$n|@uri')" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" = "404" ]; then
        printf "There is no application '%s'.\n" "${APPLICATION}"
    elif [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        FAILED=1
    fi
done
exit "${FAILED}"
