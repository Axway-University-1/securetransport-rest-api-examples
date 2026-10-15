#!/bin/bash
# ==============================================================================
# Script Name: 07.logout_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Ends the session. DELETE /myself with the cookie jar and the csrfToken (not the password), then proves it is over: the same cookie is now refused with 401.
#
# Usage:
# ./07.logout_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/02.Introduction/06.myself_DELETE.sh.
# - A logout that is not checked can look like it worked and leave the session open, so this one tries the old cookie afterwards.
# - It keeps a copy of the cookie jar for that check, and removes it.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
if [ ! -f "${JAR}" ]; then
    echo "There is no session yet: run 03.session_login_POST.sh first (or 00.run_all.sh)."
    exit 2
fi

old=$(mktemp)
trap 'rm -f "${old}"' EXIT
cp "${JAR}" "${old}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}" \
       -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)")
echo "Logout: HTTP ${code}"
[[ "${code}" == 20* ]] || exit 1
rm -f "${JAR}" "${CSRF_FILE}"

code=$(curl -k -s -o /dev/null -w "%{http_code}" -b "${old}" -X GET "${ST_URL}/myself" -H "accept: application/json" -H "Referer: ${REFERER}")
echo "The old cookie: HTTP ${code}"
if [[ "${code}" == 401 || "${code}" == 403 ]]; then
    echo "The session is over."
else
    echo "The old session still works."
    exit 1
fi
