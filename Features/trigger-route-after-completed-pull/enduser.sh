#!/bin/bash
# ==============================================================================
# Script Name: enduser.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Helpers for the End User API, loaded by settings.sh. Unlike the Admin API, the
# End User API needs a real login: POST /myself with the account's credentials
# returns a session cookie and a csrfToken header, and every later call sends
# both back.
#
# - ar_enduser_login                        log in as the test account
# - ar_enduser_call METHOD PATH TYPE [DATA] make a call in that session. Sets
#                                           AR_EU_BODY and AR_EU_CODE, and
#                                           returns 0 only for a 2xx code.
# - ar_enduser_logout                       DELETE /myself and forget the session
#
# Notes:
# - The port is AR_ENDUSER_PORT, not the Admin port.
# ==============================================================================

AR_EU_URL() { printf 'https://%s:%s/api/v2.0/%s' "${ST_SERVER}" "${AR_ENDUSER_PORT}" "$1"; }

ar_enduser_login() {
    local hdr
    AR_EU_JAR=$(mktemp)
    hdr=$(mktemp)
    AR_EU_BODY=$(curl -s -k -u "${AR_TEST_ACCOUNT}:${AR_ACCOUNT_PASSWORD}" -X POST "$(AR_EU_URL myself)" \
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
      --cookie-jar "${AR_EU_JAR}" -D "${hdr}")
    AR_EU_CODE=$(head -n 1 "${hdr}" | awk '{print $2}')
    AR_EU_CSRF=$(grep -i '^csrftoken:' "${hdr}" | tr -d '\r' | awk '{print $2}')
    case "${AR_EU_CODE}" in
        2*) rm -f "${hdr}"; printf "Logged in to the End User API as %s.\n" "${AR_TEST_ACCOUNT}"; return 0 ;;
    esac
    printf "Could not log in to the End User API as %s on port %s (HTTP %s):\n%s\n" \
      "${AR_TEST_ACCOUNT}" "${AR_ENDUSER_PORT}" "${AR_EU_CODE}" "${AR_EU_BODY}"
    printf "Response headers, which may say why:\n"
    tr -d '\r' < "${hdr}" | grep -v -i '^set-cookie' | sed 's/^/    /'
    rm -f "${hdr}"
    rm -f "${AR_EU_JAR}"
    return 1
}

ar_enduser_call() {
    local method="$1" path="$2" type="$3" data="$4" hdr
    hdr=$(mktemp)
    if [ -n "${data}" ]; then
        AR_EU_BODY=$(curl -s -k -b "${AR_EU_JAR}" -X "${method}" "$(AR_EU_URL "${path}")" \
          -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
          -H "csrfToken: ${AR_EU_CSRF}" -H "Content-Type: ${type}" -D "${hdr}" --data-binary "${data}")
    else
        AR_EU_BODY=$(curl -s -k -b "${AR_EU_JAR}" -X "${method}" "$(AR_EU_URL "${path}")" \
          -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
          -H "csrfToken: ${AR_EU_CSRF}" -D "${hdr}")
    fi
    AR_EU_CODE=$(head -n 1 "${hdr}" | awk '{print $2}')
    rm -f "${hdr}"
    case "${AR_EU_CODE}" in 2*) return 0 ;; esac
    return 1
}

ar_enduser_logout() {
    ar_enduser_call DELETE myself "" >/dev/null
    printf "Logged out (HTTP %s).\n" "${AR_EU_CODE}"
    rm -f "${AR_EU_JAR}"
}
