#!/bin/bash
# ==============================================================================
# Script Name: 01.ldapDomains_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the LDAP domains using the `/ldapDomains` endpoint: the directories
# SecureTransport can look users up in. It demonstrates:
# - Counting them, and listing them with their servers and base DN
# - One domain by its name, with name=
# - Only the ones of one protocol version, with protocolVersion=
#
# Usage:
# ./01.ldapDomains_GET.sh [NAME [PROTOCOL_VERSION]]
#
#   NAME              list the domain with exactly this name (optional)
#   PROTOCOL_VERSION  2 or 3: only the domains of this version (optional)
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - An LDAP domain only authenticates users when the server's login settings turn LDAP on
#   (see 13.Configurations/21.configurations_loginSettings_GET.sh); this script does not.
# - Confirmed directly: the answer is {resultSet, result}. name= is matched exactly:
#   no * wildcard, and not without regard to case. bindDn= too.
# - Confirmed directly: isDefault= as a filter answers an error ("The server was
#   unable to comply with your request") for true and for false. List them all and
#   read isDefault, as this script does.
# - Requires `jq`, which prints one domain per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/ldapDomains"
NAME="$1"
VERSION="$2"
if [ -n "${VERSION}" ] && ! [[ "${VERSION}" =~ ^[23]$ ]]; then
    printf "PROTOCOL_VERSION is 2 or 3, not %s.\n" "${VERSION}"
    exit 2
fi
LINE='"  \(.name)  \([.ldapServers[]? | "\(.host):\(.port)"] | join(", "))  \(.ldapSearches.baseDn // "-")  \(if .isDefault then "default" else "-" end)"'
FIELDS="name,ldapServers,ldapSearches.baseDn,isDefault"

printf "LDAP domains: "
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}?limit=1&fields=name" -H "accept: application/json" -H "${REFERER_HEADER}" \
  | jq -r '.resultSet.totalCount'

printf "\nAll of them: name, servers, base DN, default:\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "fields=${FIELDS}" \
  -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"

if [ -n "${NAME}" ]; then
    printf "\nThe one named %s:\n" "${NAME}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "name=${NAME}" --data-urlencode "fields=${FIELDS}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi

if [ -n "${VERSION}" ]; then
    printf "\nOnly the ones using LDAP version %s:\n" "${VERSION}"
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" --data-urlencode "protocolVersion=${VERSION}" --data-urlencode "fields=${FIELDS}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" | jq -r "(.result // [])[] | ${LINE}"
fi
