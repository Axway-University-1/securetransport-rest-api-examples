#!/bin/bash
# ==============================================================================
# Script Name: 03.subscriptions_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 3: two applications and two subscriptions. example_unu_app_used is the application of both subscriptions, example_unu_app_unused is the application of none. The first subscription (folder /example_unu_in) has one transfer configuration: it receives
# from the site example_unu_site_used with the transfer profile example_unu_profile_used. The second (folder /example_unu_sub_unused) has none, and step 04 will attach no route to it: it is the unused subscription.
#
# Usage:
# ./03.subscriptions_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/04.Applications/02.applications_POST.sh and Admin/API 2.0/bash/07.Subscriptions/02.subscriptions_POST.sh.
# - A subscription names its application, its site and its transfer profile by name (account and folder are what identify the subscription: it has no name).
# - Needs steps 01 and 02. An object that exists is not made again (exit 1, and it says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.subscriptions_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

for NAME in "${SITE_USED}"; do
    [ -n "$(uc_id_of sites "${NAME}")" ] || { echo "The site ${NAME} is not on the server. Run 02.partnerships_POST.sh first."; exit 1; }
done
for NAME in "${APP_USED}" "${APP_UNUSED}"; do
    [ -z "$(uc_id_of applications "${NAME}")" ] || { echo "The application ${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1; }
done
uc_get subscriptions "account=${A1}" "fields=id,folder"
if [ "${LIST_CODE}" = "200" ] && [ "$(printf '%s' "${LIST_BODY}" | jq -r '(.result // []) | length')" != "0" ]; then
    echo "${A1} has subscriptions already. Nothing more was created. Remove them with 99.cleanup_DELETE.sh."
    exit 1
fi

for NAME in "${APP_USED}" "${APP_UNUSED}"; do
    echo "Creating the application ${NAME}..."
    uc_post applications "$(jq -cn --arg name "${NAME}" '{type: "AdvancedRouting", name: $name, notes: "made by the use case identify unused objects"}')" || exit 1
done
echo "Creating the subscription ${SUB_FOLDER} (application ${APP_USED}, site ${SITE_USED}, profile ${PROFILE_USED})..."
uc_post subscriptions "$(jq -cn --arg account "${A1}" --arg app "${APP_USED}" --arg folder "${SUB_FOLDER}" --arg site "${SITE_USED}" --arg profile "${PROFILE_USED}" \
  '{type: "AdvancedRouting", account: $account, application: $app, folder: $folder, transferConfigurations: [{tag: "PARTNER-IN", outbound: false, site: $site, transferProfile: $profile}]}')" || exit 1
echo "Creating the subscription ${SUB_UNUSED_FOLDER} (application ${APP_USED}, no transfer configuration)..."
uc_post subscriptions "$(jq -cn --arg account "${A1}" --arg app "${APP_USED}" --arg folder "${SUB_UNUSED_FOLDER}" '{type: "AdvancedRouting", account: $account, application: $app, folder: $folder}')" || exit 1
