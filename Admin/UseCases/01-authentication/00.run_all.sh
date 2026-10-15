#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole use case in order (01 to 07), then 99. It stops at the first script that fails; the cleanup still runs.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
rc=0
for step in 01.basic_auth_GET_myself 02.no_credentials_GET_myself 03.session_login_POST 04.session_cookie_GET_myself 05.session_csrf_header_PATCH_myself 06.session_expired_recovery 07.logout_DELETE; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
