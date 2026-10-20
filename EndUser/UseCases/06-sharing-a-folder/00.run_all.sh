#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 07), then 99. It stops at the first script that fails; the cleanup still runs. Name the user to share with first: export ST_SHARE_WITH=their.address@example.com
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
#
# Notes:
# - Exit 3 from 01 (this account may not share) stops it, with the reason.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.sharing_GET_myself 02.folder_POST 03.folder_PATCH_share 04.folder_GET_sharing 05.folder_PATCH_rights 06.folder_PATCH_unshare 07.folder_DELETE; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
