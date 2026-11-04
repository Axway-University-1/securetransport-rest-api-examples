#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# Step 1: make something to resubmit. Two user accounts, example_rsb_a and example_rsb_b, with one generated password. In step 02 each of them uploads three files, and every upload is a
# transfer in the transfer log. The first account is for the API 2.0 (one transfer at a time), the second for the API 1.4 (many transfers with one call).
#
# Usage:
# ./01.accounts_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh (the account of type user).
# - The password is kept in state.local.password (git ignores it): 02 logs in with it on the End User API.
# - Each account is read first (HEAD): one that exists is not made again, and the script stops with exit 1 and says which. Remove them with 99.cleanup_DELETE.sh.
# - The user ids are fixed (see lib.sh): a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403). The home folders stay on the
#   server after the cleanup, so the same ids are used every time.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.accounts_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

for LINE in "${UC_ACCOUNTS[@]}"; do
    NAME="${LINE%% *}"
    case "$(uc_head "accounts/${NAME}")" in
        200) echo "${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1 ;;
        404) ;;
        *) echo "Could not tell whether ${NAME} exists. Nothing more was created."; exit 1 ;;
    esac
done

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
for LINE in "${UC_ACCOUNTS[@]}"; do
    read -r NAME UID_NUMBER <<< "${LINE}"
    echo "Creating the account ${NAME} (home /home/${NAME}, user id ${UID_NUMBER})..."
    uc_post accounts "$(jq -cn --arg name "${NAME}" --arg password "${PASSWORD}" --arg uid "${UID_NUMBER}" \
      '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: $uid, gid: $uid, user: {name: $name, passwordCredentials: {password: $password}}}')" || exit 1
done
umask 077
printf '%s' "${PASSWORD}" > "${PASSWORD_FILE}"
echo "The password of the two accounts is in $(basename "${PASSWORD_FILE}"): the server never shows it again."
