#!/bin/bash
# ==============================================================================
# Script Name: admin_calls.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# The other Admin API calls the features need besides a POST (post_admin.sh), shared
# across Features/ and loaded by each feature's settings.sh, after post_admin.sh.
#
# - ar_admin_delete PATH   DELETE PATH on the Admin API and print the response and the
#                          HTTP code. Returns 0 only for a 2xx code, so a caller ends
#                          with `|| exit 1`, or keeps what could not be deleted.
# - ar_admin_exists PATH   HEAD PATH and print nothing. Returns 0 when it answers 200,
#                          1 when it answers 404, 2 for anything else (the server did
#                          not answer, or refused): then nobody knows, and a clean-up
#                          must not say "nothing to delete".
#
# Both set AR_ADMIN_CODE to the HTTP code of the call (000 when there was no answer at
# all). PATH is encoded by segment, like in ar_enduser_call.
#
# Notes:
# - Needs ST_SERVER, ST_PORT, ST_USER and ST_PASSWORD, and ar_encode_path from
#   post_admin.sh.
# ==============================================================================

ar_admin_delete() {
    local hdr code
    hdr=$(mktemp)
    curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "https://${ST_SERVER}:${ST_PORT}/api/v2.0/$(ar_encode_path "$1")" \
      -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -D "${hdr}"
    code=$(head -n 1 "${hdr}" | awk '{print $2}')
    rm -f "${hdr}"
    code="${code:-000}"
    AR_ADMIN_CODE="${code}"
    printf "\nHTTP %s\n" "${code}"
    case "${code}" in
        2*) return 0 ;;
    esac
    return 1
}

ar_admin_exists() {
    local code
    code=$(curl -s -k -o /dev/null -w "%{http_code}" -u "${ST_USER}:${ST_PASSWORD}" --head \
      "https://${ST_SERVER}:${ST_PORT}/api/v2.0/$(ar_encode_path "$1")" -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT")
    AR_ADMIN_CODE="${code:-000}"
    case "${code}" in
        200) return 0 ;;
        404) return 1 ;;
    esac
    return 2
}
