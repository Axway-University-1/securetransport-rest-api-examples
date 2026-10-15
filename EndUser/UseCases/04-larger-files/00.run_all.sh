#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 06), then 99. It stops at the first script that fails; the cleanup still runs.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.folder_POST 02.files_POST_md5 03.fileOperations_POST_md5calc 04.fileOperations_PUT_chunked 05.fileOperations_POST_multipart 06.files_POST_bulk; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
