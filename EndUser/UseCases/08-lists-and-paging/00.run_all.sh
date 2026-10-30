#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: 01 to 06, then the cleanup.
#
# Usage:
# ./00.run_all.sh [COUNT] [LIMIT]
#
#   COUNT  how many files 01 uploads, 1 to 20 (default 7)
#   LIMIT  entries per page for the walks of 02 and 03, 1 or more (default 3)
#
# Risk: write
#
# Notes:
# - The inputs are checked first: a wrong COUNT or LIMIT stops it at once, with the usage, before any call.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# - Exit 3 from 03 (the account may not use the transfers web service) is not a failure: the step is skipped, with its reason, and the run goes on.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [COUNT] [LIMIT]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: COUNT and LIMIT.\n%s\n" "$#" "${USAGE}"; exit 2; fi
COUNT="${1:-7}"
LIMIT="${2:-3}"
if [[ ! "${COUNT}" =~ ^[1-9][0-9]?$ ]] || [ "${COUNT}" -gt 20 ]; then
    printf "COUNT is '%s': it must be a whole number from 1 to 20.\n%s\n" "${COUNT}" "${USAGE}"
    exit 2
fi
if [[ ! "${LIMIT}" =~ ^[1-9][0-9]*$ ]]; then
    printf "LIMIT is '%s': it must be a whole number of 1 or more.\n%s\n" "${LIMIT}" "${USAGE}"
    exit 2
fi
rc=0
for step in "01.files_POST_location ${COUNT}" "02.files_GET_list ${LIMIT}" "03.transfers_GET_list ${LIMIT}" "04.addressBook_GET" "05.fields_not_offered" "06.counting_without_totalCount"; do
    set -- ${step}
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}"
    code=$?
    if [ "${code}" = "3" ]; then
        echo "$1 was skipped: the account may not use this part."
    elif [ "${code}" != "0" ]; then
        rc=1; echo "$1 failed."; break
    fi
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
