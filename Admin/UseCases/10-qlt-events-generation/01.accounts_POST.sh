#!/bin/bash
# ==============================================================================
# Script Name: 01.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Step 1: the account that makes the transfers. One user account, example_qlt, with one generated password. In step 04 it uploads and downloads a file, and every one of those is a transfer
# the server reports to Sentinel as events. The overflow file of step 03 is in its home folder, so it is also the account that reads the events.
#
# Usage:
# ./01.accounts_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/02.accounts_POST.sh (the account of type user).
# - The password is kept in state.local.password (git ignores it): the End User calls of the later steps log in with it.
# - The account is read first (HEAD): one that exists already is not made again, and the script stops with exit 1. Remove it with 99.cleanup_DELETE.sh.
# - The user id is fixed (see lib.sh): a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.accounts_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

case "$(uc_head "accounts/${ACCOUNT}")" in
    200) echo "${ACCOUNT} exists already. Nothing was created. Remove it with 99.cleanup_DELETE.sh."; exit 1 ;;
    404) ;;
    *) echo "Could not tell whether ${ACCOUNT} exists. Nothing was created."; exit 1 ;;
esac

PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
echo "Creating the account ${ACCOUNT} (home /home/${ACCOUNT}, user id ${ACCOUNT_UID})..."
uc_post accounts "$(jq -cn --arg name "${ACCOUNT}" --arg password "${PASSWORD}" --arg uid "${ACCOUNT_UID}" \
  '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: $uid, gid: $uid, user: {name: $name, passwordCredentials: {password: $password}}}')" || exit 1
umask 077
printf '%s' "${PASSWORD}" > "${PASSWORD_FILE}"
echo "The password is in $(basename "${PASSWORD_FILE}"): the server never shows it again."
