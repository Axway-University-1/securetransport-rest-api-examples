#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 09), then 99. It stops at the first script that fails; the cleanup still runs.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.folder_POST 02.files_POST_upload 03.files_GET_list 04.files_GET_read 05.files_GET_metadata 06.files_POST_overwrite 07.files_PATCH_rename 08.files_DELETE_file 09.folder_DELETE; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
