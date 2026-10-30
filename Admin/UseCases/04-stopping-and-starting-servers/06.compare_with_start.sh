#!/bin/bash
# ==============================================================================
# Script Name: 06.compare_with_start.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Stopping and starting, step 6: prove that everything is as it was. Reads the daemons and the servers again and compares them with the copy step 01 saved. It prints each difference and
# exits 1 when there is one; the answer "nothing is different" is the proof that the use case left the server as it found it.
#
# Usage:
# ./06.compare_with_start.sh
#
# Risk: read
#
# Notes:
# - Written for this use case (the same two reads as 01.daemons_GET.sh).
# - Without a saved copy (step 01 was not run) there is nothing to compare with: the script says so and exits 1.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./06.compare_with_start.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ ! -s "${DAEMONS_STATE}" ] || [ ! -s "${SERVERS_STATE}" ]; then
    echo "There is no saved copy of the start ($(basename "${DAEMONS_STATE}") and $(basename "${SERVERS_STATE}")): run 01.daemons_GET.sh first. Nothing to compare."
    exit 1
fi
st_session

result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X GET "${ST_URL}/daemons" -H "accept: application/json" -H "Referer: ${REFERER}")
code=${result: -3}
echo "GET /daemons: HTTP ${code}"
[[ "${code}" == 200 ]] || { echo "${result%???}"; exit 1; }
DAEMONS_NOW=$(printf '%s' "${result%???}" | jq -S .)
uc_read_servers || exit 1
echo "GET /servers: HTTP 200"
SERVERS_NOW=$(printf '%s' "${SERVERS_JSON}" | jq -S 'sort_by(.serverName)')

differences=0
while IFS=$'\t' read -r key before after; do
    [ -n "${key}" ] || continue
    printf "  DIFFERENT: the %s daemon was %s and is %s\n" "${key%Status}" "${before}" "${after}"
    differences=$((differences + 1))
done < <(jq -r -n --slurpfile a "${DAEMONS_STATE}" --argjson b "${DAEMONS_NOW}" '$a[0] as $x | ($x | keys[]) as $k | select($x[$k] != $b[$k]) | [$k, $x[$k], ($b[$k] // "missing")] | @tsv')
while IFS=$'\t' read -r key before after; do
    [ -n "${key}" ] || continue
    printf "  DIFFERENT: the server %s was %s and is %s\n" "${key}" "${before}" "${after}"
    differences=$((differences + 1))
done < <(jq -r -n --slurpfile a "${SERVERS_STATE}" --argjson b "${SERVERS_NOW}" \
          '$a[0][] as $x | ($b | map(select(.serverName == $x.serverName)) | first // null) as $y | select($y == null or $y.isActive != $x.isActive) | [$x.serverName, (if $x.isActive then "active" else "not active" end), (if $y == null then "gone" else (if $y.isActive then "active" else "not active" end) end)] | @tsv')
while IFS= read -r name; do
    [ -n "${name}" ] || continue
    printf "  DIFFERENT: the server %s was not there and is now\n" "${name}"
    differences=$((differences + 1))
done < <(jq -r -n --slurpfile a "${SERVERS_STATE}" --argjson b "${SERVERS_NOW}" '$b[] | select(.serverName as $n | $a[0] | all(.serverName != $n)) | .serverName')

if [ "${differences}" -ne 0 ]; then
    echo "${differences} difference(s) from the start. 99.cleanup_DELETE.sh puts a daemon and its servers back."
    exit 1
fi
echo "Nothing is different: every daemon and every server is as at the start."
