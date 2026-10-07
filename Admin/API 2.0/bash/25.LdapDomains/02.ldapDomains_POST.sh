#!/bin/bash
# ==============================================================================
# Script Name: 02.ldapDomains_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script adds an LDAP domain using the `/ldapDomains` endpoint: a directory
# server, the account SecureTransport binds with, and where it searches for users.
#
# Usage:
# ./02.ldapDomains_POST.sh [NAME [HOST [PORT]]]
#
#   NAME  the domain's name (default example_ldap)
#   HOST  the directory server (default: the SecureTransport server itself)
#   PORT  its port (default 389)
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An LDAP domain only authenticates users when the server's login settings turn LDAP on
#   (see 13.Configurations/21.configurations_loginSettings_GET.sh); this script does not.
# - LDAP_BIND_PASSWORD, the password of the bind account, is read from the environment,
#   so set it first:
#     export LDAP_BIND_PASSWORD='the bind password'
# - The bind account is cn=reader,dc=example,dc=com and the base DN is
#   ou=People,dc=example,dc=com: change BIND_DN and BASE_DN below for a real directory.
# - Confirmed directly: bindDn and bindDnPassword are required, though the reference
#   marks only name. A name that exists answers 409 "Duplicate domain".
# - Confirmed directly: the server looks the host up when the domain is saved, so a name
#   it cannot resolve answers 400 "Invalid server host". An address always works.
# - Confirmed directly: the defaults are not the reference's: referralsAllowed and
#   anonymousBindsAllowed both read true.
# - The answer is 201, with the new domain's ID, not its name, at the end of Location, and
#   no body. 08.ldapDomains_name_operations_POST_testConnection.sh tries the connection.
# - Requires `jq`, which builds the body.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="${1:-example_ldap}"
HOST="${2:-${ST_SERVER}}"
PORT="${3:-389}"
BIND_DN="cn=reader,dc=example,dc=com"
BASE_DN="ou=People,dc=example,dc=com"
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}"' EXIT
if [ -z "${LDAP_BIND_PASSWORD}" ]; then
    printf "Set LDAP_BIND_PASSWORD to the bind account's password first.\n"
    exit 2
fi
if [ -z "${NAME// /}" ] || [ -z "${HOST// /}" ]; then
    printf "NAME and HOST must not be blank.\n"
    exit 2
fi
if ! [[ "${PORT}" =~ ^[0-9]+$ ]] || [ "${PORT}" -gt 65535 ]; then
    printf "PORT is a number up to 65535: %s\n" "${PORT}"
    exit 2
fi

BODY=$(jq -cn --arg name "${NAME}" --arg host "${HOST}" --argjson port "${PORT}" --arg dn "${BIND_DN}" --arg password "${LDAP_BIND_PASSWORD}" --arg base "${BASE_DN}" \
  '{name: $name, description: "Created by 25.LdapDomains", protocolVersion: 3, bindDn: $dn, bindDnPassword: $password,
    ldapServers: [{host: $host, port: $port}], ldapSearches: {baseDn: $base, searchAttribute: "UID"}}')

printf "Adding the LDAP domain %s, directory at %s:%s...\n" "${NAME}" "${HOST}" "${PORT}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf "Its id: %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | sed 's|.*/||')"
