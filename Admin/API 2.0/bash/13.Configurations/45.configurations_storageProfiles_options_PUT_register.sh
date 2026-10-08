#!/bin/bash
# ==============================================================================
# Script Name: 45.configurations_storageProfiles_options_PUT_register.sh
# Author: Plamen Milenkov
# Created: 2026-10-06
# Location: Sofia
# ==============================================================================
# Description:
# This script adds an S3 storage profile, example_s3: a bucket the server can
# keep files in, named by account home folders, sites and business units.
# There is no storage profile resource; a profile is Server Configuration
# Options, set here with the `/configurations/options` endpoint and PUT.
#
# Usage:
# ./45.configurations_storageProfiles_options_PUT_register.sh BUCKET [REGION [ENDPOINT]]
#
#   BUCKET    the bucket
#   REGION    its region (default us-east-1)
#   ENDPOINT  an S3-compatible service's address, for example
#             http://s3.example.com:9000 (default: AWS itself)
#
# Risk: config
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - S3_ACCESS_KEY and S3_SECRET_KEY are read from the environment; leave them
#   unset to use the AWS default credentials of the server.
# - It adds example_s3 to the option StorageProfiles.S3.Registry, which
#   creates the profile's own options, StorageProfiles.S3.Registry.example_s3.*
#   (Bucket, Region, CustomEndpointUrl, AccessKey, SecretKey, ...), then sets
#   them.
# - Confirmed directly: saving the profile tests the connection: a bucket the
#   server cannot reach answers 400 "Connection to S3 storage using supplied
#   setting failed" and nothing is saved.
# - 47.configurations_storageProfiles_options_PUT_unregister.sh removes it.
# - tests/integration/lib/dummy_servers.py has a FakeS3 that can stand in for an
#   S3 bucket to try these examples against.
# - Requires `jq`, which reads the registry and builds the bodies.
# - The registry is read first, and the script stops (exit 1) when it cannot be read: sending a registry made of this one profile alone would drop the
#   others. Confirmed directly: when the settings of the profile are then refused (400, a bucket that cannot be reached), the name is in the registry all the
#   same, with every one of its options empty: the script says so, and 47.configurations_storageProfiles_options_PUT_unregister.sh takes it out.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/configurations"
BUCKET="$1"
REGION="${2:-us-east-1}"
ENDPOINT="$3"
PROFILE="example_s3"
[ -n "${BUCKET}" ] || { printf "Usage: ./45.configurations_storageProfiles_options_PUT_register.sh BUCKET [REGION [ENDPOINT]]\n"; exit 2; }

# The profiles already registered, plus this one
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}/options/StorageProfiles.S3.Registry" \
  -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the registry of storage profiles (HTTP %s), so nothing was changed.\n" "${HTTP_CODE}"
    exit 1
fi
REGISTRY=$(printf '%s' "${RESPONSE}" | jq -c --arg profile "${PROFILE}" '[(.values // [])[] | select(. != "")] + [$profile] | unique')
BODY=$(jq -cn --argjson values "${REGISTRY}" '[{name: "StorageProfiles.S3.Registry", values: $values}]')
printf "Registering %s; the registry becomes %s\n" "${PROFILE}" "${REGISTRY}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/options" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    exit 1
fi

P="StorageProfiles.S3.Registry.${PROFILE}"
BODY=$(jq -cn --arg p "${P}" --arg bucket "${BUCKET}" --arg region "${REGION}" --arg endpoint "${ENDPOINT}" \
  --arg access "${S3_ACCESS_KEY}" --arg secret "${S3_SECRET_KEY}" '[
  {name: "\($p).Bucket", values: [$bucket]},
  {name: "\($p).Region", values: [$region]},
  {name: "\($p).CustomEndpointUrl", values: [$endpoint]},
  {name: "\($p).AccessKey", values: [$access]},
  {name: "\($p).SecretKey", values: [$secret]}]')
printf "Setting its bucket %s, region %s%s...\n" "${BUCKET}" "${REGION}" "${ENDPOINT:+, endpoint ${ENDPOINT}}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PUT "${MAIN_URL}/options" -H "accept: */*" -H "${REFERER_HEADER}" \
  -H "Content-Type: application/json" -d "${BODY}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "204" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}"
    printf "%s is in the registry all the same, without its settings: 47.configurations_storageProfiles_options_PUT_unregister.sh removes it.\n" "${PROFILE}"
    exit 1
fi
