#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-28
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: 01 to 06, then the cleanup.
#
# Usage:
# ./00.run_all.sh [NAME] [EMAIL]
#
#   NAME   the account to onboard; it must start with example_ (default example_onboard)
#   EMAIL  its first email address (default NAME@example.com)
#
# Risk: write
#
# Notes:
# - The inputs are checked first: a name that is not example_* stops it at once, with the usage, before any call.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh [NAME] [EMAIL]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: NAME and EMAIL.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-example_onboard}"
EMAIL="${2:-${NAME}@example.com}"
if [[ ! "${NAME}" =~ ^example_[A-Za-z0-9._-]+$ ]]; then
    printf "NAME is '%s': it must start with example_ and hold only letters, digits, '.', '_' and '-'.\n%s\n" "${NAME}" "${USAGE}"
    exit 2
fi
rc=0
for step in "01.accounts_POST ${NAME} ${EMAIL}" "02.accounts_GET ${NAME}" "03.accounts_PATCH ${NAME}" "04.enduser_login_GET ${NAME}" "05.enduser_home_POST ${NAME}" "06.accounts_DELETE ${NAME}"; do
    set -- ${step}
    printf '\n=== %s ===\n' "$1"
    bash "${DIR}/$1.sh" "${@:2}" || { rc=1; echo "$1 failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh" "${NAME}"
exit ${rc}
