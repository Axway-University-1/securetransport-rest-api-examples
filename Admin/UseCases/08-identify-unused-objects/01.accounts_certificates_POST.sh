#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_certificates_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 1, something to look at: two accounts and two certificates. example_unu_a1 is the account that will have every relation (a site, a transfer profile, subscriptions, a composite route); example_unu_a2 will have none.
# The certificates belong to a1: example_unu_cert_used (step 02 gives it to a site) and example_unu_cert_unused (nothing will name it). Each is a key pair that openssl makes here, packed as PKCS#12 and imported with usage private.
#
# Usage:
# ./01.accounts_certificates_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh (the accounts) and Admin/API 2.0/bash/11.Certificates/03.certificates_POST_import_partner.sh (the multipart/mixed import), with usage private and a PKCS#12 file.
# - A site can name only a local or private certificate (a certificate with a key): a partner or login certificate is refused (400 "The certificate should be local or private."). That is why the certificates are PKCS#12.
# - The password of a1 is generated and kept in state.local.password (git ignores it): 05 logs in with it on the End User API. The user ids are fixed: a home folder keeps the uid of its first owner.
# - Each object is read first (HEAD or a name search): one that exists is not made again, and the script stops with exit 1 and says which. Remove them with 99.cleanup_DELETE.sh.
# - Deleting an account deletes its certificates too. Needs openssl and jq.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.accounts_certificates_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
command -v openssl >/dev/null 2>&1 || { echo "openssl is needed to make the key pairs of the two certificates, and it is not installed."; exit 1; }
st_session

for NAME in "${A1}" "${A2}"; do
    CODE=$(uc_head "accounts/${NAME}")
    case "${CODE}" in
        200) echo "${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1 ;;
        404) ;;
        *) echo "Could not tell whether ${NAME} exists (HTTP ${CODE}). Nothing was created."; exit 1 ;;
    esac
done

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
for LINE in "${A1} ${A1_UID}" "${A2} ${A2_UID}"; do
    read -r NAME ID <<< "${LINE}"
    echo "Creating the account ${NAME} (home /home/${NAME}, user id ${ID})..."
    uc_post accounts "$(jq -cn --arg name "${NAME}" --arg password "${PASSWORD}" --arg id "${ID}" \
      '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: $id, gid: $id, user: {name: $name, passwordCredentials: {password: $password}}}')" || exit 1
done
umask 077
printf '%s' "${PASSWORD}" > "${PASSWORD_FILE}"
echo "The password of ${A1} is in $(basename "${PASSWORD_FILE}"): the server never shows it again."

WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
for NAME in "${CERT_USED}" "${CERT_UNUSED}"; do
    if [ -n "$(uc_id_of certificates "${NAME}")" ]; then echo "The certificate ${NAME} exists already. Remove it with 99.cleanup_DELETE.sh."; exit 1; fi
    echo "Making a key pair for ${NAME} and importing it for ${A1}..."
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" -days 30 -subj "/CN=${NAME}" >/dev/null 2>&1 ||
        { echo "openssl could not make the key pair."; exit 1; }
    openssl pkcs12 -export -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" -out "${WORK}/${NAME}.p12" -passout "pass:${P12_PASSWORD}" >/dev/null 2>&1 ||
        { echo "openssl could not make the PKCS#12 file."; exit 1; }
    CODE=$(uc_import_cert "${NAME}" "${A1}" "${WORK}/${NAME}.p12" "${P12_PASSWORD}")
    if [ "${CODE}" != "200" ] && [ "${CODE}" != "201" ]; then
        echo "POST /certificates: HTTP ${CODE}: ${NAME} was not imported."
        exit 1
    fi
    echo "  HTTP ${CODE}, imported as a private certificate of ${A1}: id $(uc_id_of certificates "${NAME}")"
done
