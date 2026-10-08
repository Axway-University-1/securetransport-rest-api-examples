#!/bin/bash
# ==============================================================================
# Script Name: enduser.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Helpers for the End User API, shared across Features/, loaded by each feature's
# settings.sh. Unlike the Admin API, the
# End User API needs a real login: POST /myself with the account's credentials
# returns a session cookie and a csrfToken header, and every later call sends
# both back.
#
# Reads EU_ACCOUNT, EU_ACCOUNT_PASSWORD and EU_ENDUSER_PORT - neutral names, not
# any one feature's own prefix. Each feature's settings.sh sets these as aliases
# of its own prefixed variables before sourcing this file.
#
# - ar_enduser_login                        log in as the test account
# - ar_enduser_call METHOD PATH TYPE [DATA] make a call in that session. Sets
#                                           AR_EU_BODY and AR_EU_CODE, and
#                                           returns 0 only for a 2xx code. Each
#                                           segment of PATH is URL-encoded (see
#                                           ar_encode_path in post_admin.sh), so a
#                                           file name from a listing with a space
#                                           or a # in it reaches the server whole.
# - ar_enduser_logout                       DELETE /myself and forget the session
#
# Notes:
# - The port is EU_ENDUSER_PORT, not the Admin port.
# - Confirmed directly (5.5-20260924): a file name from a listing with a # in it, put into the URL
#   as it is, cuts the path short: DELETE /files/dir/a#1.txt asks for /dir/a and is a 404 "Unable
#   to delete file: /dir/a. (file not found)". A space makes curl send nothing (code 000). With each
#   segment encoded (a%231.txt, my%20file%231.txt) the GET and the DELETE both work.
# - A path with a ? in it cannot carry a query string: the ? is encoded like the
#   rest. No example here needs one.
# - Needs ar_encode_path, from post_admin.sh, which settings.sh loads first.
# ==============================================================================

AR_EU_URL() { printf 'https://%s:%s/api/v2.0/%s' "${ST_SERVER}" "${EU_ENDUSER_PORT}" "$1"; }

ar_enduser_login() {
    local hdr
    AR_EU_JAR=$(mktemp)
    hdr=$(mktemp)
    AR_EU_BODY=$(curl -s -k -u "${EU_ACCOUNT}:${EU_ACCOUNT_PASSWORD}" -X POST "$(AR_EU_URL myself)" \
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
      --cookie-jar "${AR_EU_JAR}" -D "${hdr}")
    AR_EU_CODE=$(head -n 1 "${hdr}" | awk '{print $2}')
    AR_EU_CODE="${AR_EU_CODE:-000}"
    AR_EU_CSRF=$(grep -i '^csrftoken:' "${hdr}" | tr -d '\r' | awk '{print $2}')
    case "${AR_EU_CODE}" in
        2*) rm -f "${hdr}"; printf "Logged in to the End User API as %s.\n" "${EU_ACCOUNT}"; return 0 ;;
    esac
    printf "Could not log in to the End User API as %s on port %s (HTTP %s):\n%s\n" \
      "${EU_ACCOUNT}" "${EU_ENDUSER_PORT}" "${AR_EU_CODE}" "${AR_EU_BODY}"
    printf "Response headers, which may say why:\n"
    tr -d '\r' < "${hdr}" | grep -v -i '^set-cookie' | sed 's/^/    /'
    rm -f "${hdr}"
    rm -f "${AR_EU_JAR}"
    return 1
}

ar_enduser_call() {
    local method="$1" path="$2" type="$3" data="$4" hdr url
    hdr=$(mktemp)
    url=$(AR_EU_URL "$(ar_encode_path "${path}")")
    if [ -n "${data}" ]; then
        AR_EU_BODY=$(curl -s -k -b "${AR_EU_JAR}" -X "${method}" "${url}" \
          -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
          -H "csrfToken: ${AR_EU_CSRF}" -H "Content-Type: ${type}" -D "${hdr}" --data-binary "${data}")
    else
        AR_EU_BODY=$(curl -s -k -b "${AR_EU_JAR}" -X "${method}" "${url}" \
          -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" \
          -H "csrfToken: ${AR_EU_CSRF}" -D "${hdr}")
    fi
    AR_EU_CODE=$(head -n 1 "${hdr}" | awk '{print $2}')
    AR_EU_CODE="${AR_EU_CODE:-000}"
    rm -f "${hdr}"
    case "${AR_EU_CODE}" in 2*) return 0 ;; esac
    return 1
}

ar_enduser_logout() {
    ar_enduser_call DELETE myself "" >/dev/null
    printf "Logged out (HTTP %s).\n" "${AR_EU_CODE}"
    rm -f "${AR_EU_JAR}"
}
