#!/bin/bash
# ==============================================================================
# Script Name: 02.accounts_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates accounts using the `/accounts` endpoint.
# It demonstrates creating one account of each type, all of them harmless examples:
# - user: example_user, with a password of your own (from the environment) or a generated one that is printed
# - service: example_service
# - template: example_template, in a user class that exists on the server (given, or looked up)
#
# Usage:
# [export ACCOUNT_PASSWORD='the password of example_user']
# ./02.accounts_POST.sh [TEMPLATE_CLASS]
#
#   ACCOUNT_PASSWORD  the password of example_user, from the environment (optional): when it is not set, one is generated and printed
#   TEMPLATE_CLASS    the user class of the template account (default: the first class of the server whose type is not real,
#                     looked up with GET /userClasses; VirtClass is never assumed)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The three accounts are example_user, example_service and example_template, so running this bare changes nothing that matters. 07.accounts_name_DELETE.sh removes them.
#   The other scripts of this folder act on example_user by default.
# - A template account needs a user class (`templateClass`). It is taken from the first argument, or looked up: the classes of the server are read first and the first one of type
#   `virtual` (or `*`) is used, by its `order`. If there is none, the script says so and sends nothing (exit 1). Confirmed directly: a class that does not exist is accepted by the
#   server all the same (see 36.UserClasses), so a given class is not checked.
# - The password is never in the file. A generated one (12 random letters and digits after a fixed beginning that satisfies a password policy) is printed once.
# - The uid and gid are fixed at 41733 on purpose: a home folder outlives its account and keeps the uid it was created with, so a later account of the same name
#   with another uid could not create a folder in it (a 403, see st-api-gotchas, "A home folder outlives its account").
# - Requires `jq`, which looks the class up and builds each body.
# - Confirmed directly: each creation answers 201 with no body and the new account's address in `Location`; a second one with the same name is 409
#   "Unable to create account 'example_user': The account name is not unique." A user account created this way has the address book sources LDAP and Local already.
# - Exit codes: 0 when all three were created (201), 1 when the server refuses one (the others are still tried) or no user class can be found, 2 when an argument is wrong (nothing sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
USER_NAME="example_user"
SERVICE_NAME="example_service"
TEMPLATE_NAME="example_template"
USAGE="Usage: [ACCOUNT_PASSWORD='...'] ./02.accounts_POST.sh [TEMPLATE_CLASS]"
TEMPLATE_CLASS="$1"

if [ "$#" -gt 1 ]; then
    printf "%s\n" "${USAGE}"
    exit 2
fi

PASSWORD="${ACCOUNT_PASSWORD}"
GENERATED=""
if [ -z "${PASSWORD}" ]; then
    PASSWORD="Ex1!$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)"
    GENERATED="yes"
fi

if [ -z "${TEMPLATE_CLASS}" ]; then
    printf "Looking up a user class for the template account...\n"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses" \
      --data-urlencode "fields=className,userType,order" -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" = "200" ]; then
        TEMPLATE_CLASS=$(printf '%s' "${RESPONSE}" | jq -r '[(.result // [])[] | select(.userType != "real")] | sort_by(.order) | .[0].className // empty')
    fi
    if [ -z "${TEMPLATE_CLASS}" ]; then
        printf "Could not find a user class for the template account (HTTP %s). Nothing was created: give one as the first argument.\n" "${HTTP_CODE}"
        exit 1
    fi
    printf "Using the user class %s.\n" "${TEMPLATE_CLASS}"
fi

FAILED=0

# create_account DESCRIPTION BODY
create_account() {
    printf "Creating %s...\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "$2" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        FAILED=1
    fi
}

# Simple POST to create an Account of type User
BODY=$(jq -cn --arg name "${USER_NAME}" --arg password "${PASSWORD}" \
  '{name: $name, type: "user", homeFolder: ("/home/" + $name), uid: "41733", gid: "41733", user: {name: $name, passwordCredentials: {password: $password}}}')
create_account "an Account of type User (${USER_NAME})" "${BODY}"

# Simple POST to create an Account of type Service
BODY=$(jq -cn --arg name "${SERVICE_NAME}" '{name: $name, type: "service", homeFolder: ("/home/" + $name), uid: "41733", gid: "41733"}')
create_account "an Account of type Service (${SERVICE_NAME})" "${BODY}"

# Simple POST to create an Account of type Template, with the user class found above
BODY=$(jq -cn --arg name "${TEMPLATE_NAME}" --arg class "${TEMPLATE_CLASS}" \
  '{name: $name, type: "template", homeFolder: ("/home/" + $name), uid: "41733", gid: "41733", templateClass: $class}')
create_account "an Account of type Template (${TEMPLATE_NAME})" "${BODY}"

if [ -n "${GENERATED}" ]; then
    printf "The password of %s is %s (generated: it is not shown again).\n" "${USER_NAME}" "${PASSWORD}"
fi
exit "${FAILED}"
