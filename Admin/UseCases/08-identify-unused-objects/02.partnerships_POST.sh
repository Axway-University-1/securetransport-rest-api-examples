#!/bin/bash
# ==============================================================================
# Script Name: 02.partnerships_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 2: three transfer sites and two transfer profiles for example_unu_a1 (and a fourth site, a PeSIT site, that the server asks for before it makes a transfer profile). example_unu_site_used will be used by a subscription (step 03), and it names the certificate example_unu_cert_used. example_unu_site_step will be named by a route step
# (step 04). example_unu_site_unused will be named by nothing. example_unu_profile_used will be named by a subscription, example_unu_profile_unused by nothing.
#
# Usage:
# ./02.partnerships_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/06.TransferSites/02.sites_POST_ssh.sh (an ssh site with a password, here towards 192.0.2.1, an address reserved for examples: nothing ever connects) and
#   Admin/API 2.0/bash/35.TransferProfiles/02.transferProfiles_POST.sh.
# - A site names its certificate by id in clientCertificate: the id is read from the name of the certificate that step 01 imported.
# - A transfer profile is a PeSIT thing: the server refuses one for an account that has no PeSIT site (400 "Account does not contain any PeSIT transfer sites."). So the script makes example_unu_pesit_support first. The use case skips
#   PeSIT and AS2 sites when it looks for unused ones (they can be used only to receive, a relation that the configuration does not show), so that site is never reported.
# - Needs step 01. An object that exists is not made again (exit 1, and it says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.partnerships_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

CERT_ID=$(uc_id_of certificates "${CERT_USED}")
[ -n "${CERT_ID}" ] || { echo "The certificate ${CERT_USED} is not on the server. Run 01.accounts_certificates_POST.sh first."; exit 1; }
for NAME in "${SITE_USED}" "${SITE_STEP}" "${SITE_UNUSED}" "${SITE_PESIT}"; do
    [ -z "$(uc_id_of sites "${NAME}")" ] || { echo "The site ${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1; }
done
for NAME in "${PROFILE_USED}" "${PROFILE_UNUSED}"; do
    [ -z "$(uc_id_of transferProfiles "${NAME}")" ] || { echo "The transfer profile ${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1; }
done

site_body() {    # NAME CERTIFICATE_ID or "": an ssh site of a1; the certificate only when one is given
    jq -cn --arg name "$1" --arg account "${A1}" --arg cert "$2" \
      '{type: "ssh", protocol: "ssh", name: $name, account: $account, host: "192.0.2.1", port: "22", userName: "partner", usePassword: true, password: "not-a-real-password",
        transferType: "partner", uploadFolder: "/delivered"} + (if $cert != "" then {clientCertificate: $cert} else {} end)'
}
echo "Creating the site ${SITE_USED}, with the certificate ${CERT_USED}..."
uc_post sites "$(site_body "${SITE_USED}" "${CERT_ID}")" || exit 1
for NAME in "${SITE_STEP}" "${SITE_UNUSED}"; do
    echo "Creating the site ${NAME}..."
    uc_post sites "$(site_body "${NAME}" "")" || exit 1
done
echo "Creating the PeSIT site ${SITE_PESIT} (a transfer profile needs one)..."
uc_post sites "$(jq -cn --arg name "${SITE_PESIT}" --arg account "${A1}" '{type: "pesit", protocol: "pesit", name: $name, account: $account, host: "192.0.2.1", port: "17617", transferType: "partner"}')" || exit 1
for NAME in "${PROFILE_USED}" "${PROFILE_UNUSED}"; do
    echo "Creating the transfer profile ${NAME}..."
    uc_post transferProfiles "$(jq -cn --arg name "${NAME}" --arg account "${A1}" '{name: $name, account: $account, sendMapping: "/*", fileLabelOption: "DONT_SEND"}')" || exit 1
done
