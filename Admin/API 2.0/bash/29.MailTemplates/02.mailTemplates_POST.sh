#!/bin/bash
# ==============================================================================
# Script Name: 02.mailTemplates_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script adds a mail template using the `/mailTemplates` endpoint: it uploads an
# XHTML file as a multipart form, with a name and a description.
#
# Usage:
# ./02.mailTemplates_POST.sh [NAME [FILE [DESCRIPTION]]]
#
#   NAME         the template's name, ending in .xhtml (default example_mail.xhtml)
#   FILE         the XHTML file to upload (default: a small one the script writes)
#   DESCRIPTION  its description (default: Created by 29.MailTemplates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: name and file are both required (400 "Name can't be empty." and
#   "File can't be empty."). The body must be a multipart form: JSON answers 415.
# - Confirmed directly: the name must end in .xhtml (400 "Valid Mail Template name is not empty and
#   with file extension xhtml."). It is case sensitive: example_mail.xhtml and EXAMPLE_MAIL.xhtml
#   are two templates. A name that exists answers 409 "Template with name ... already exists." A name
#   of 300 characters answers 400 "Database error creating mail template"; a space is fine.
# - Confirmed directly: a name with a / in it is accepted by POST, but the entry can then not be addressed by any path (%2F answers 400) and so not deleted. The script refuses a / or \ in a name.
# - Confirmed directly: although the reference says the uploaded file's own name is ignored, the
#   server checks it: a file not named *.xhtml answers 400 "Invalid mail template file, only .xhtml
#   name extensions are supported." The script sends the file under the template's name, so any
#   local file will do. The content is not checked at all: an empty file, or plain text, is accepted.
# - Confirmed directly: the answer is 201, the address in Location, and no body. A description left
#   out reads back as null.
# - A mail template is plain XHTML; the ones the server ships carry the Velocity settings of the
#   e-mail in comments, e.g. <!-- #set( $subject = "...") -->.
# - Requires `jq`, which prints the error.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/mailTemplates"
NAME="${1:-example_mail.xhtml}"
FILE="$2"
DESCRIPTION="${3-Created by 29.MailTemplates}"
SAMPLE_FILE=""
HEADERS_FILE=$(mktemp)
trap 'rm -f "${HEADERS_FILE}" "${SAMPLE_FILE}"' EXIT

if [ -z "${NAME// /}" ] || [[ "${NAME}" == */* ]] || [[ "${NAME}" == *\\* ]]; then
    printf "NAME must not be blank, and must not hold a / or a \\: %s\n" "${NAME}"
    exit 2
fi
if [[ "${NAME}" != *.xhtml ]]; then
    printf "NAME must end in .xhtml: %s\n" "${NAME}"
    exit 2
fi
if [ -z "${FILE}" ]; then
    SAMPLE_FILE=$(mktemp)
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><title></title></head><body><p>$MESSAGE</p></body></html>\n' > "${SAMPLE_FILE}"
    FILE="${SAMPLE_FILE}"
elif [ ! -f "${FILE}" ]; then
    printf "There is no file %s.\n" "${FILE}"
    exit 2
fi

printf "Adding the mail template %s from %s...\n" "${NAME}" "${FILE}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
  -F "file=@${FILE};type=application/xhtml+xml;filename=${NAME}" --form-string "name=${NAME}" --form-string "description=${DESCRIPTION}" \
  -D "${HEADERS_FILE}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
printf "HTTP %s\n" "${HTTP_CODE}"
if [ "${HTTP_CODE}" != "201" ]; then
    printf '%s\n' "${RESPONSE%$'\n'*}" | jq -r '.validationErrors[0] // .message // .' 2>/dev/null
    exit 1
fi
printf "Its address ends: %s\n" "$(sed -n 's/^[Ll]ocation: *//p' "${HEADERS_FILE}" | tr -d '\r' | sed 's|.*/||')"
