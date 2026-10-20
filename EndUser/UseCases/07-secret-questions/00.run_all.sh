#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 05), then 99. It stops at the first script that fails; the cleanup still runs. Without ST_SECRET_ANSWER it stops at 03, before changing the account.
#
# Usage:
# [ST_SECRET_ANSWER='an answer'] ./00.run_all.sh
#
# Risk: write
#
# Notes:
# - Exit 3 from 01 means the secret question service is not enabled on the server.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.secretQuestions_GET 02.secretQuestion_GET_mine 03.secretQuestion_PUT 04.secretQuestion_GET_back 05.secretQuestion_PUT_refused; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh"
    code=$?
    # 02 answers 4 for an account with no question yet: that is the starting point, not a failure
    if [ "${code}" -ne 0 ] && ! { [ "${step}" = "02.secretQuestion_GET_mine" ] && [ "${code}" -eq 4 ]; }; then
        rc=1; echo "${step} failed."; break
    fi
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
