#!/bin/bash
# ==============================================================================
# Script Name: 02.userClasses_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script creates a user class using the `/userClasses` endpoint.
# It demonstrates:
# - A class that matches one login name (the userName), with an optional membership expression
# - That it is created disabled unless you say so, so that it cannot catch a login by accident
# - Reading the new class's address from the Location header
#
# Usage:
# ./02.userClasses_POST.sh [NAME [USER_NAME [EXPRESSION [ENABLED [USER_TYPE]]]]]
#
#   NAME        the class's name, no spaces (default example_userclass)
#   USER_NAME   the login names it matches; takes a * wildcard, is case sensitive (default example_nobody)
#   EXPRESSION  a membership expression; none (default) leaves it out. Quote it
#   ENABLED     true or false (default false)
#   USER_TYPE   * (default, any), real or virtual
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A user class decides which class an account is in when it logs in. The server tries the classes in `order` and the
#   FIRST enabled one that matches wins; a class matches when its userType, userName, group and address fit the login
#   and its expression (when there is one) is true. The lab has two classes of its own, VirtClass (virtual) and RealClass
#   (real), that match every login of their type: never change or delete them.
# - Run 07.userClasses_id_DELETE.sh to remove what this creates. An enabled class with a wide USER_NAME takes the logins of
#   every account it fits, and a new class is put FIRST, before VirtClass and RealClass: the script refuses an enabled class
#   whose USER_NAME is *.
# - Confirmed directly: a success is 201 with the new class's address in `Location` and no body. Required: `className`,
#   `userType`, `userName`, `group` and `address` (the 400 lists each one missing). The reference's text says `host`, but the
#   field is `address` (`host` is 400 "Unsupported parameter - host", as is any unknown field). `enabled` defaults to false and
#   `expression` to the empty text; `order` in the body is IGNORED: the new class is put first (order 1) and the others move down
#   one, VirtClass and RealClass too (they move back when it is deleted).
# - Confirmed directly: a duplicate name is 409 "User class with this name already exists.", but names are case sensitive
#   (`example_x` and `EXAMPLE_X` coexist). A blank name is 400 "className is empty.", a name with a space 400 "className contains
#   whitespace."; dashes, dots and accents are accepted, and so is a name of 33 characters though the reference says 32. `userType`
#   is exactly `*`, `real` or `virtual` (400 "Valid userType values are: *, real and virtual"). An empty userName, group or address
#   is 400. `enabled` may be the text "true"; "abc" is 400.
# - Confirmed directly: the expression is CHECKED when it is saved: 400 "expression X is not valid." for `1==1`, `user.name == "bob"`,
#   `a && b`, `a || b`, `!a`, `gt`, `nonsense(` and a string method on a literal. It accepts `true`, `false`, `1 > 0`, `a and b`,
#   `a or b`, `isset("A") ? x : y`, `memberof("CN=..",LDAP_DIR_memberOf$collection)` and a bare name or a method on one
#   (`user.name.startsWith("a")`): the check is of the syntax, an unknown name is not refused. It is at most 1024 characters
#   (400 "expression size must be between 0 and 1024").
# - Confirmed directly, what it does: an SFTP, an EndUser API (HTTP) or an FTP login (same result over all three) of an account whose name fits is put in the class (the sessions list shows it
#   as `userClass`: `GET /sessions?fields=userName,userClass`, see 32.Sessions), one that does not fit stays in VirtClass. `userName` is a pattern (`*_ab12`,
#   `example_a*`), case sensitive; `userType` virtual fits a local account and real does not; `address` is the client's address, exact or
#   with a `*` at the end (the first part of the address, then `.*`); a `group` that is not the account's, `enabled` false and an expression that is false do not match.
#   The expression is true for `true`, `1 > 0`, `true or false`, and false for `false`, `2 > 3`, `not true` and any attribute test
#   (`isset("LDAP_DIR_memberOf")`, `memberof(..)`): a local account has no directory attributes, and its additionalAttributes are not
#   visible to an expression. Membership by an LDAP attribute was therefore NOT seen on the lab.
# - Requires `jq`, which builds the request body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/userClasses"
NAME="${1:-example_userclass}"
USER_NAME="${2:-example_nobody}"
EXPRESSION="${3:-none}"
ENABLED="${4:-false}"
USER_TYPE="${5:-*}"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${NAME// /}" ] || [[ "${NAME}" =~ [[:space:]] ]]; then
    printf "NAME must not be empty or hold a space.\n"
    exit 2
fi
if [ -z "${USER_NAME}" ]; then
    printf "USER_NAME must not be empty.\n"
    exit 2
fi
case "${ENABLED}" in
    true|false) ;;
    *) printf "ENABLED is true or false, not %s.\n" "${ENABLED}"; exit 2 ;;
esac
case "${USER_TYPE}" in
    '*'|real|virtual) ;;
    *) printf "USER_TYPE is *, real or virtual, not %s.\n" "${USER_TYPE}"; exit 2 ;;
esac
if [ "${ENABLED}" = "true" ] && [ "${USER_NAME}" = "*" ]; then
    printf "An enabled class for every user name would take the login of every account (a new class is tried first). Refused.\n"
    exit 2
fi
if [ "${#EXPRESSION}" -gt 1024 ]; then
    printf "EXPRESSION is 1024 characters at most.\n"
    exit 2
fi

# expression is left out when there is none
BODY=$(jq -cn --arg name "${NAME}" --arg user "${USER_NAME}" --arg type "${USER_TYPE}" --arg expression "${EXPRESSION}" --argjson enabled "${ENABLED}" \
  '{className: $name, userType: $type, userName: $user, group: "*", address: "*", enabled: $enabled}
   + (if $expression != "none" then {expression: $expression} else {} end)')

printf "Creating the user class %s for the login names %s...\n" "${NAME}" "${USER_NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi
printf "It is at %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r')"
