#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 04), then 99. It stops at the first script that fails; the cleanup still runs.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.transfers_GET 02.transfers_GET_filtered 03.transfers_id_GET 04.transfers_summary; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
