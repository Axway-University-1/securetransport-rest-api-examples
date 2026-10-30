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
# ./00.run_all.sh [RESOURCE] [PAGE_SIZE]
#
#   RESOURCE   the list that 01 to 04 read (default accounts)
#   PAGE_SIZE  entries per call for the walk in 02, 1 or more (default 5)
#
# Risk: write
#
# Notes:
# - The inputs are checked first: a wrong RESOURCE or PAGE_SIZE stops it at once, with the usage, before any call.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# - It makes five throwaway business units (05) and removes them (99).
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [RESOURCE] [PAGE_SIZE]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: RESOURCE and PAGE_SIZE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
RESOURCE="${1:-accounts}"
PAGE_SIZE="${2:-5}"
if [[ ! "${RESOURCE}" =~ ^[A-Za-z][A-Za-z0-9/_-]*$ ]]; then
    printf "RESOURCE is '%s': it is the path of a resource, such as accounts or logs/transfers.\n%s\n" "${RESOURCE}" "${USAGE}"
    exit 2
fi
if [[ ! "${PAGE_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
    printf "PAGE_SIZE is '%s': it must be a whole number of 1 or more.\n%s\n" "${PAGE_SIZE}" "${USAGE}"
    exit 2
fi
rc=0
for step in "01.list_default_GET ${RESOURCE}" "02.paging_walk ${RESOURCE} ${PAGE_SIZE}" "03.fields_GET ${RESOURCE}" "04.head_exists ${RESOURCE}" "05.location_POST" "06.filters_GET"; do
    set -- ${step}
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}" || { rc=1; echo "$1 failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
