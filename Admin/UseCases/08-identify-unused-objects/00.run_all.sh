#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Runs the use case from start to finish: 01 to 04 make the objects, 05 runs a transfer, 06 disables a route, 07 to 09 find the unused objects among the demo set, 10 does the same on the whole server (read only), then the cleanup.
#
# Usage:
# ./00.run_all.sh
#
# Risk: write
#
# Notes:
# - It takes no parameter. Set ST_ENDUSER_PORT in set_variables.local.sh when the End User port is not the admin port minus one (05 logs in as the account a1 on it). Needs openssl.
# - It stops at the first step that fails, says which, and still runs 99.cleanup_DELETE.sh.
# - 10 reads the whole server, page by page: it takes longer on a big server. Everything it does there is read only.
# - The transfer of step 05 stays in the transfer log and the server log after the cleanup.
# ==============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
USAGE="Usage: ./00.run_all.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
rc=0
for step in 01.accounts_certificates_POST 02.partnerships_POST 03.subscriptions_POST 04.routes_POST 05.upload_POST 06.step_PATCH_disable \
            07.map_relationships_GET 08.server_log_search_GET 09.unused_objects_GET 10.whole_server_GET; do
    printf '\n=== %s ===\n' "${step}"
    bash "${DIR}/${step}.sh" || { rc=1; echo "${step} failed."; break; }
done
printf '\n=== 99.cleanup_DELETE ===\n'
bash "${DIR}/99.cleanup_DELETE.sh"
exit ${rc}
