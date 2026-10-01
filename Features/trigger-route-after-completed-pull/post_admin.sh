#!/bin/bash
# ==============================================================================
# Script Name: post_admin.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Two small helpers shared by the examples in this folder, loaded by settings.sh.
#
# - ar_admin_post PATH BODY [STATE_KEY]   POST to the Admin API and print the
#   response and the HTTP code. On success, the id of the new object is read
#   from the Location header and saved under STATE_KEY.
# - ar_state_get STATE_KEY                print a saved id.
#
# Notes:
# - Ids are kept in state.local.sh, next to this file, which git ignores. A later
#   example reads the ids an earlier one saved, and 99.cleanup_DELETE.sh uses
#   them to delete what was created.
# ==============================================================================

AR_STATE_FILE="$(dirname "${BASH_SOURCE[0]}")/state.local.sh"

ar_state_set() {
    printf 'export %s=%q\n' "$1" "$2" >> "${AR_STATE_FILE}"
}

ar_state_get() {
    [ -f "${AR_STATE_FILE}" ] && ( source "${AR_STATE_FILE}"; eval "printf '%s' \"\${$1}\"" )
}

ar_admin_post() {
    local path="$1" body="$2" key="$3" hdr code location id
    hdr=$(mktemp)
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/${path}" \
      -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "Content-Type: application/json" \
      -D "${hdr}" -d "${body}"
    code=$(head -n 1 "${hdr}" | awk '{print $2}')
    location=$(grep -i '^location:' "${hdr}" | tr -d '\r' | awk '{print $2}')
    rm -f "${hdr}"
    printf "\nHTTP %s\n" "${code}"
    case "${code}" in
        2*) ;;
        *)  return 1 ;;
    esac
    id="${location##*/}"
    if [ -n "${key}" ] && [ -n "${id}" ]; then
        ar_state_set "${key}" "${id}"
        printf "Saved %s = %s\n" "${key}" "${id}"
    fi
    return 0
}
