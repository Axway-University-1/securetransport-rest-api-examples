#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 07), then 99, sharing with EMAIL and trying each type of share on the way: first the RIGHTS given (read by default), then write, then full. It stops at the first script that fails; the cleanup still runs. Without EMAIL, or with RIGHTS that is not valid, it stops at once, before anything is done.
#
# Usage:
# ./00.run_all.sh EMAIL [RIGHTS]
#
# Risk: write
#
# Notes:
# - EMAIL is the e-mail address of a user the server knows. It is required: without it (exit 2) nothing is run, not even the login, and nothing is created.
# - Exit 3 from 01 (this account may not share) stops it, with the reason.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
EMAIL="$1"
RIGHTS="${2:-read}"
case "${RIGHTS}" in read|write|full|1|3|7) ;; *) RIGHTS="" ;; esac
if [ -z "${EMAIL}" ] || [ -z "${RIGHTS}" ]; then
    printf "Usage: ./00.run_all.sh EMAIL [RIGHTS]\n"
    printf "  EMAIL   the e-mail address of a user the server knows: the folder is shared with them\n"
    printf "  RIGHTS  the first type of share: read (1, the default), write (3) or full (7)\n"
    printf "Nothing was done: the whole run needs the address, so it is asked for before anything is created.\n"
    exit 2
fi
rc=0
# each step: the script, then its arguments
STEPS=("01.sharing_GET_myself" "02.folder_POST" "03.folder_PATCH_share ${EMAIL} ${RIGHTS}" "04.folder_GET_sharing"
       "05.folder_PATCH_rights write" "05.folder_PATCH_rights full" "04.folder_GET_sharing" "06.folder_PATCH_unshare" "07.folder_DELETE")
for step in "${STEPS[@]}"; do
    set -- ${step}
    script="$1"; shift
    printf '\n=== %s %s ===\n' "${script}" "$*"
    bash "${DIR}/${script}.sh" "$@" || { rc=1; echo "${script} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
