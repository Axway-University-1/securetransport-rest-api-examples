#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: 01 to 11, then the cleanup.
#
# Usage:
# ./00.run_all.sh [NAME]
#
#   NAME  the account to make and change; the route is NAME_route. It must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - The name is checked first: one that is not example_* stops it at once, with the usage, before any call.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh (which also puts back the option of step 11).
# - 11 changes one server option for a moment and puts it back; it takes its own default option and value.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-example_chg}"
if [[ ! "${NAME}" =~ ^example_[A-Za-z0-9._-]+$ ]]; then
    printf "NAME is '%s': it must start with example_ and hold only letters, digits, '.', '_' and '-'.\n%s\n" "${NAME}" "${USAGE}"
    exit 2
fi
rc=0
for step in 01.object_POST 02.object_GET 03.patch_string 04.patch_number 05.patch_boolean 06.patch_list 07.patch_null_and_object 08.patch_mistakes 09.put_whole_object 10.put_fragment 11.options_save_change_restore; do
    printf '\n=== %s ===\n' "${step}"
    if [ "${step}" = "11.options_save_change_restore" ]; then
        bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
    else
        bash "${DIR}/${step}.sh" "${NAME}" || { rc=1; echo "${step} failed."; break; }
    fi
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh" "${NAME}" || rc=1
exit ${rc}
