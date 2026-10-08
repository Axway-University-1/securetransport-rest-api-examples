#!/bin/bash
# ==============================================================================
# Script Name: post_admin.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Small helpers shared across Features/, loaded by each feature's settings.sh.
#
# - ar_admin_post PATH BODY [STATE_KEY]   POST to the Admin API and print the
#   response and the HTTP code. On success, the id of the new object is read
#   from the Location header and saved under STATE_KEY. Returns 0 only for a
#   2xx code, so a caller ends with `|| exit 1`.
# - ar_state_get STATE_KEY                print a saved id.
# - ar_encode_path PATH                   print PATH with each segment URL-encoded
#   (a space, a # or a ? in a name must not end the path early); the / between
#   the segments stays. Needs jq.
#
# Sets AR_ADMIN_CODE to the HTTP code of the last call (000 when there was no
# answer at all).
#
# Notes:
# - Ids are kept in state.local.sh, next to the feature's own scripts (not next to
#   this file), which git ignores. A later
#   example reads the ids an earlier one saved, and 99.cleanup_DELETE.sh uses
#   them to delete what was created.
# ==============================================================================

# FEATURE_DIR is set by the feature's own settings.sh, before this is sourced,
# so the state file lands next to that feature's scripts, not in this shared lib.
AR_STATE_FILE="${FEATURE_DIR}/state.local.sh"

ar_state_set() {
    printf 'export %s=%q\n' "$1" "$2" >> "${AR_STATE_FILE}"
}

ar_state_get() {
    [ -f "${AR_STATE_FILE}" ] && ( source "${AR_STATE_FILE}"; eval "printf '%s' \"\${$1}\"" )
}

# ar_encode_path PATH: every segment encoded on its own, the / between them kept
ar_encode_path() {
    printf '%s' "$1" | jq -Rr 'split("/") | map(@uri) | join("/")'
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
    code="${code:-000}"
    AR_ADMIN_CODE="${code}"
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
