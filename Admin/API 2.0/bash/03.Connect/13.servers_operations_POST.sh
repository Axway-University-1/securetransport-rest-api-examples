#!/bin/bash
# ==============================================================================
# Script Name: 13.servers_operations_POST.sh
# Author: Plamen Milenkov
# Created: 2025-08-06
# Location: Sofia
# ==============================================================================
# Description:
# This script manages server operations using the `/servers/operations` endpoint.
# It demonstrates:
# - Starting servers that are currently stopped
# - Starting daemons required for server activation
#
# Usage:
# ./13.servers_operations_POST.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Daemons must be running for certain servers to start successfully.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

printf "Getting the list of servers...\n"
ALL_SERVERS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers?fields=serverName,isActive" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json")
NUMBER_OF_SERVERS=$(echo "${ALL_SERVERS}" | jq '.result | length')

printf "Found %s servers\n" "${NUMBER_OF_SERVERS}"

for i in $(seq 0 $((NUMBER_OF_SERVERS - 1))); do
    NAME=$(echo "${ALL_SERVERS}" | jq -r ".result[$i].serverName")
    IS_ACTIVE=$(echo "${ALL_SERVERS}" | jq -r ".result[$i].isActive")
    if [ "${IS_ACTIVE}" == "true" ]; then
        printf "Server: %s is running\n" "${NAME}"
    else
        printf "Server: %s is not running\n" "${NAME}"
    fi
    if [ "${IS_ACTIVE}" == "false" ]; then
        printf "Starting server %s...\n" "${NAME}"
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/servers/operations?serverName=${NAME}&operation=start" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
    fi
done

function start_daemon {
    DAEMON_STATUS=$1
    DAEMON_NAME=$2
    if [ "${DAEMON_STATUS}" == "Not running" ]; then
        printf "Starting daemon %s...\n" "${DAEMON_NAME}"
        curl -k -u "${ST_USER}:${ST_PASSWORD}" -X "POST" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons/operations?operation=start&daemon=${DAEMON_NAME}" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json"
    else
        printf "Daemon %s is running\n" "${DAEMON_NAME}"
    fi
}

printf "Getting the list of daemons...\n"
ALL_DAEMONS=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X "GET" "https://${ST_SERVER}:${ST_PORT}/api/v2.0/daemons" -H "accept: application/json" -H "${REFERER_HEADER}" -H "Content-Type: application/json")
echo "${ALL_DAEMONS}"

#
# Note the use of 'jq -r' so that the status is returned without the surrounding
# double quotes, which keeps the comparison in start_daemon straightforward.
#
start_daemon "$(echo "${ALL_DAEMONS}" | jq -r '.sshStatus')" "ssh"
start_daemon "$(echo "${ALL_DAEMONS}" | jq -r '.as2Status')" "as2"
start_daemon "$(echo "${ALL_DAEMONS}" | jq -r '.pesitStatus')" "pesit"
start_daemon "$(echo "${ALL_DAEMONS}" | jq -r '.ftpStatus')" "ftp"
start_daemon "$(echo "${ALL_DAEMONS}" | jq -r '.httpStatus')" "http"
