#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-11-04
# Location: Sofia
# ==============================================================================
# Description:
# Removes what this use case made: the two accounts example_rsb_a and example_rsb_b, and the files of the use case (the session, the password, the time window). It is safe to run twice: an
# account that is not there (404) is fine.
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/05.Accounts/07.accounts_name_DELETE.sh.
# - The names are the exact ones of lib.sh, never a pattern.
# - The transfers stay in the transfer log, and the home folders stay on the server: the log is not something the API deletes, and a home folder outlives its account.
# - After this cleanup the transfers of the two accounts can no longer be resubmitted: tried, the 1.4 call answers an ERROR for each (see the README).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

rc=0
for LINE in "${UC_ACCOUNTS[@]}"; do
    NAME="${LINE%% *}"
    code=$(uc_delete "accounts/${NAME}")
    case "${code}" in
        204) echo "The account ${NAME} was deleted." ;;
        404) echo "The account ${NAME} was not there." ;;
        *) echo "The account ${NAME} could not be deleted (HTTP ${code}): delete it by hand."; rc=1 ;;
    esac
done
curl -k -s -o /dev/null -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
rm -f "${JAR}" "${CSRF_FILE}" "${PASSWORD_FILE}" "${WINDOW_FILE}"
echo "Cleaned up. The transfers stay in the transfer log."
exit "${rc}"
