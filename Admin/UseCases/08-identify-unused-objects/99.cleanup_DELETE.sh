#!/bin/bash
# ==============================================================================
# Script Name: 99.cleanup_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Deletes what the steps made, by exact name, and the files of this folder that hold state, and ends the administrator's session. It can be run twice. What it does not remove: the entries that the transfers of step 05 and the requests of the steps left
# in the logs, and the home folders of the two accounts (a home folder outlives its account, and keeps the user id of its first owner).
#
# Usage:
# ./99.cleanup_DELETE.sh
#
# Risk: write
#
# Notes:
# - Written for this use case. Every name is example_unu_*; nothing else is touched.
# - The composite routes go first: deleting a composite route also deletes the simple routes its steps run (the server does it). The simple routes that no step runs (the orphan) are deleted one by one. Then the subscriptions, the templates, the
#   applications, the sites, the transfer profiles and the accounts (an account takes its certificates with it).
# - An object that is not there (404) is not an error: it was deleted already.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.cleanup_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

STATUS=0
remove() {      # RESOURCE NAME: delete the object of that exact name (an account or an application is addressed by its name, the others by their id)
    local id code
    id=$(uc_id_of "$1" "$2")
    if [ -z "${id}" ]; then echo "${2} is not there."; return; fi
    case "$1" in accounts|applications) code=$(uc_delete "$1/$2") ;; *) code=$(uc_delete "$1/${id}") ;; esac
    case "${code}" in
        204) echo "${2} was deleted." ;;
        404) echo "${2} is not there." ;;
        *) echo "${2} could not be deleted (HTTP ${code}): delete it by hand."; STATUS=1 ;;
    esac
}
for NAME in "${COMP_USED}" "${COMP_UNUSED}"; do remove routes "${NAME}"; done
uc_get subscriptions "account=${A1}" "fields=id,folder"
if [ "${LIST_CODE}" = "200" ]; then
    for ID in $(printf '%s' "${LIST_BODY}" | jq -r '(.result // [])[] | select(.folder | startswith("/example_unu_")) | .id'); do
        CODE=$(uc_delete "subscriptions/${ID}")
        case "${CODE}" in 204|404) echo "The subscription ${ID} was deleted (HTTP ${CODE})." ;; *) echo "The subscription ${ID} could not be deleted (HTTP ${CODE})."; STATUS=1 ;; esac
    done
fi
for NAME in "${RT_ON}" "${RT_OLD}" "${RT_NEVER}" "${RT_ORPHAN}"; do remove routes "${NAME}"; done
for NAME in "${TPL_USED}" "${TPL_UNUSED}"; do remove routes "${NAME}"; done
for NAME in "${APP_USED}" "${APP_UNUSED}"; do remove applications "${NAME}"; done
for NAME in "${PROFILE_USED}" "${PROFILE_UNUSED}"; do remove transferProfiles "${NAME}"; done
for NAME in "${SITE_USED}" "${SITE_STEP}" "${SITE_UNUSED}" "${SITE_PESIT}"; do remove sites "${NAME}"; done
for NAME in "${A1}" "${A2}"; do remove accounts "${NAME}"; done
rm -rf "${MAP_DIR}" "${MAP_ALL_DIR}" "${PASSWORD_FILE}"

CODE=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
echo "The administrator's session was ended (HTTP ${CODE})."
rm -f "${JAR}" "${CSRF_FILE}"
exit ${STATUS}
