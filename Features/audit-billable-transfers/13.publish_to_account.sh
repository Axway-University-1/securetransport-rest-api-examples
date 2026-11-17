#!/bin/bash
# ==============================================================================
# Script Name: 13.publish_to_account.sh
# Author: Plamen Milenkov
# Created: 2026-11-11
# Location: Sofia
# ==============================================================================
# Description:
# One more scenario, 2.7, with a single Publish to Account step: a file that
# the test account receives is published by the server, with no partner and no
# network, to a folder of another account on the same server,
# partner_to_push_to. It creates what the scenario needs (the folder, the
# subscription, a route with the one step, a composite route that links them) and
# sets that account's home folder access level to PUBLIC while it runs,
# uploads one file to the test account's folder, waits for it to arrive in the
# other account, and prints the billable count of both accounts before and
# after, with the transfers behind it.
#
# Usage:
# ./13.publish_to_account.sh [ACCOUNT]
#
#   ACCOUNT   the test account (default: the one of settings.sh). Run
#             00.run_all.sh first: this needs its account, application and
#             route template.
#
# Risk: write
#
# Notes:
# - Needs the objects of 00.run_all.sh, and BT_ACCOUNT_PASSWORD (see settings.sh).
# - The step is the API's `Publish` step (the product's "Publish to Account"):
#   targetAccountExpression is the other account, targetFolderExpression a
#   folder in it that the step makes when it is not there.
# - The route and the subscription are named after the test account like the
#   others (<account>SimpleRoute7, <account>CompositeRoute7), so
#   99.cleanup_DELETE.sh removes them, and the folders, with the rest.
# - The upload goes to a subscription folder of the test account: that is what
#   starts the route. No pull site is needed.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
if [ -n "$1" ]; then
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "$1"; exit 2; }
    export BT_RUN_ACCOUNT="$1"
fi
source "${SCRIPT_DIR}/settings.sh"

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi
TEMPLATE_ID=$(ar_state_get BT_ID_TEMPLATE)
if [ -z "${TEMPLATE_ID}" ]; then
    printf "BT_ID_TEMPLATE is not saved. Run 00.run_all.sh first.\n"
    exit 1
fi

W=$(mktemp -d)
trap 'rm -rf "${W}"' EXIT

# today_count ACCOUNT: the billable transfers of today, from the report script
today_count() {
    "${SCRIPT_DIR}/billable_GET_report.sh" "$1" "${BT_TEST_ACCOUNT}" | sed -n "s/^TODAY_COUNT $2: //p"
}

# The folder, in the test account, that starts the route
printf "Creating the folder %s in %s...\n" "${BT_PUBLISH_SOURCE_FOLDER}" "${BT_TEST_ACCOUNT}"
bt_login_as "${BT_TEST_ACCOUNT}" || exit 1
ar_enduser_call POST "files/${BT_PUBLISH_SOURCE_FOLDER#/}" "application/json" \
  '{"isDirectory": true, "isRegularFile": false, "isSymbolicLink": false, "isOther": false, "isShared": false}'
printf "HTTP %s\n" "${AR_EU_CODE}"
case "${AR_EU_CODE}" in 2*) ;; 409) printf "The folder is there already: going on.\n" ;; *) printf "%s\n" "${AR_EU_BODY}"; ar_enduser_logout; exit 1 ;; esac
ar_enduser_logout

# The other account must accept files from another account. A Private home
# folder (the default) refuses the step: "It can only receive files from itself"
# (log AR0057), and the step fails with "Not allowed to publish files to home
# folder of target account". So it is set to PUBLIC for this scenario, and put
# back afterwards. The folder in it is made by the step.
ADMIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0"
# set_level ACCOUNT LEVEL: PATCH the home folder access level, the HTTP code is printed
set_level() {
    curl -s -k -o /dev/null -w '%{http_code}' -X PATCH -u "${ST_USER}:${ST_PASSWORD}" \
      -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "Content-Type: application/json" \
      -d "$(jq -n --arg v "$2" '[{op: "replace", path: "/homeFolderAccessLevel", value: $v}]')" \
      "${ADMIN_URL}/accounts/$1"
}
OLD_LEVEL=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
  "${ADMIN_URL}/accounts/${BT_PUSH_PARTNER}" | jq -r '.homeFolderAccessLevel // empty')
restore_level() {
    if [ -n "${OLD_LEVEL}" ] && [ "${OLD_LEVEL}" != "PUBLIC" ]; then
        printf "Putting the home folder access level of %s back to %s: HTTP %s\n" \
          "${BT_PUSH_PARTNER}" "${OLD_LEVEL}" "$(set_level "${BT_PUSH_PARTNER}" "${OLD_LEVEL}")"
        OLD_LEVEL=""
    fi
}
trap 'restore_level; rm -rf "${W}"' EXIT
if [ "${OLD_LEVEL}" != "PUBLIC" ]; then
    printf "Setting the home folder access level of %s to PUBLIC (it was %s)...\n" "${BT_PUSH_PARTNER}" "${OLD_LEVEL:-unknown}"
    LEVEL_CODE=$(set_level "${BT_PUSH_PARTNER}" PUBLIC)
    printf "HTTP %s\n" "${LEVEL_CODE}"
    case "${LEVEL_CODE}" in 2*) ;; *) exit 1 ;; esac
fi

# The subscription on that folder, the route with the one step, and the composite
# route that links the two (the same three objects as the other scenarios)
SUB_BODY=$(jq -n --arg account "${BT_TEST_ACCOUNT}" --arg application "${BT_APPLICATION}" \
  --arg folder "${BT_PUBLISH_SOURCE_FOLDER}" \
  '{type: "AdvancedRouting", application: $application, account: $account, folder: $folder}')
printf "Creating the subscription on %s...\n" "${BT_PUBLISH_SOURCE_FOLDER}"
ar_admin_post "subscriptions" "${SUB_BODY}" "BT_ID_SUBSCRIPTION_7" || exit 1

STEP=$(jq -n --arg account "${BT_PUSH_PARTNER}" --arg folder "${BT_PUBLISHED_FOLDER#/}" \
  '{type: "Publish", status: "ENABLED", conditionType: "ALWAYS", autostart: false,
    usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
    filenameCollisionResolutionType: "OVERWRITE",
    targetAccountExpressionType: "NAME", targetAccountExpression: $account,
    targetFolderExpressionType: "SIMPLE", targetFolderExpression: $folder,
    triggerSubscription: false, actionOnStepFailure: "FAIL"}')
SIMPLE_BODY=$(jq -n --arg name "${BT_SIMPLE_ROUTE_PREFIX}7" --argjson step "${STEP}" \
  '{type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true, steps: [$step]}')
printf "Creating the simple route %s, with one Publish step to %s...\n" "${BT_SIMPLE_ROUTE_PREFIX}7" "${BT_PUSH_PARTNER}"
ar_admin_post "routes" "${SIMPLE_BODY}" "BT_ID_SIMPLE_7" || exit 1

COMPOSITE_BODY=$(jq -n --arg name "${BT_COMPOSITE_ROUTE_PREFIX}7" --arg account "${BT_TEST_ACCOUNT}" \
  --arg template "${TEMPLATE_ID}" --arg sub "$(ar_state_get BT_ID_SUBSCRIPTION_7)" \
  --arg simple "$(ar_state_get BT_ID_SIMPLE_7)" \
  '{type: "COMPOSITE", account: $account, name: $name, conditionType: "MATCH_ALL",
    routeTemplate: $template, subscriptions: [$sub],
    steps: [{type: "ExecuteRoute", status: "ENABLED", autostart: false, executeRoute: $simple}]}')
printf "Creating the composite route %s...\n" "${BT_COMPOSITE_ROUTE_PREFIX}7"
ar_admin_post "routes" "${COMPOSITE_BODY}" "BT_ID_COMPOSITE_7" || exit 1

RUN_START=$(LC_ALL=C date '+%a, %d %b %Y %H:%M:%S %z')
printf "\nBillable transfers of today, before:\n"
BEFORE_TEST=$(today_count before "${BT_TEST_ACCOUNT}")
BEFORE_PUSH=$(today_count before "${BT_PUSH_PARTNER}")
printf "  %-24s %s\n  %-24s %s\n" "${BT_TEST_ACCOUNT}" "${BEFORE_TEST:-?}" "${BT_PUSH_PARTNER}" "${BEFORE_PUSH:-?}"

# One file into the folder: the subscription starts the route, the route publishes
printf "\nUploading %s to %s of %s...\n" "${BT_FILE_PUBLISH}" "${BT_PUBLISH_SOURCE_FOLDER}" "${BT_TEST_ACCOUNT}"
printf 'Scenario 2.7: published to another account.\n' > "${W}/${BT_FILE_PUBLISH}"
bt_login_as "${BT_TEST_ACCOUNT}" || exit 1
ar_enduser_call POST fileOperations "application/json" \
  "$(jq -n --arg path "${BT_PUBLISH_SOURCE_FOLDER}/${BT_FILE_PUBLISH}" '{operation: "Upload", filePath: $path, customAttributes: {transferMode: "BINARY"}}')"
OPERATION=$(printf '%s' "${AR_EU_BODY}" | jq -r '.id // empty' 2>/dev/null)
if [ -z "${OPERATION}" ]; then
    printf "No operation id came back (HTTP %s):\n%s\n" "${AR_EU_CODE}" "${AR_EU_BODY}"
    ar_enduser_logout
    exit 1
fi
ar_enduser_call PUT "fileOperations/${OPERATION}" "application/octet-stream" "@${W}/${BT_FILE_PUBLISH}"
printf "HTTP %s\n" "${AR_EU_CODE}"
ar_enduser_logout

# Wait for the file in the other account
printf "\nWaiting for %s in %s of %s...\n" "${BT_FILE_PUBLISH}" "${BT_PUBLISHED_FOLDER}" "${BT_PUSH_PARTNER}"
bt_login_as "${BT_PUSH_PARTNER}" || exit 1
FOUND=0
waited=0
while true; do
    ar_enduser_call GET "files${BT_PUBLISHED_FOLDER}" ""
    FOUND=$(printf '%s' "${AR_EU_BODY}" | jq --arg n "${BT_FILE_PUBLISH}" \
      '[(.files // [])[] | select(.isRegularFile and .fileName == $n)] | length' 2>/dev/null)
    [ "${FOUND:-0}" -ge 1 ] && break
    [ "${waited}" -ge "${BT_WAIT_SECONDS}" ] && break
    sleep 3
    waited=$((waited + 3))
done
ar_enduser_logout
if [ "${FOUND:-0}" -lt 1 ]; then
    printf "The file did not arrive within %s seconds.\n" "${BT_WAIT_SECONDS}"
    exit 1
fi
printf "%s is in %s of %s.\n" "${BT_FILE_PUBLISH}" "${BT_PUBLISHED_FOLDER}" "${BT_PUSH_PARTNER}"

sleep "${BT_STEP_PAUSE_SECONDS}"
printf "\nBillable transfers of today, after:\n"
AFTER_TEST=$(today_count after "${BT_TEST_ACCOUNT}")
AFTER_PUSH=$(today_count after "${BT_PUSH_PARTNER}")
printf "  %-24s %s (added %s)\n  %-24s %s (added %s)\n" \
  "${BT_TEST_ACCOUNT}" "${AFTER_TEST:-?}" "$(( ${AFTER_TEST:-0} - ${BEFORE_TEST:-0} ))" \
  "${BT_PUSH_PARTNER}" "${AFTER_PUSH:-?}" "$(( ${AFTER_PUSH:-0} - ${BEFORE_PUSH:-0} ))"

# The transfers behind the numbers, by file name
printf "\nThe transfers of %s:\n" "${BT_FILE_PUBLISH}"
SINCE="${RUN_START}"
for account in "${BT_TEST_ACCOUNT}" "${BT_PUSH_PARTNER}"; do
    curl -s -k -G -u "${ST_USER}:${ST_PASSWORD}" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/logs/transfers" \
      --data-urlencode "account=${account}" --data-urlencode "startTimeAfter=${SINCE}" --data-urlencode "limit=200" \
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
      | jq -r --arg n "${BT_FILE_PUBLISH}" \
          '(.result // [])[] | select((.filename // "") == $n)
           | "  " + .account + "  coreId " + (.coreId[0:8]) + "  billable " + (.isBillable|tostring) + "  " + (.protocol // "") + "  " + (.status // "")'
done
