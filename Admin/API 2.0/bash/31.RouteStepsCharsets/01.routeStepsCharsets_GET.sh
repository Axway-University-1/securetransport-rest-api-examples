#!/bin/bash
# ==============================================================================
# Script Name: 01.routeStepsCharsets_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the character sets a route step can use, with the
# `/routeStepsCharsets` endpoint.
# It demonstrates:
# - Counting the character sets and listing them, one per line
# - Asking whether one name is in the list
# - Checking the `inputCharset` and `outputCharset` of a route step (or of every step of a route) in a JSON file
#   against the list, before the step is sent to the server
#
# Usage:
# ./01.routeStepsCharsets_GET.sh [CHARSET | step FILE]
#
#   CHARSET  a character set name to look for, as written, e.g. UTF-8 (optional)
#   step FILE  a JSON file holding one step, an array of steps, or a route with a `steps` array: every
#              inputCharset and outputCharset in it is looked up, one line each (optional)
#
# Risk: read - the only operation of this resource is a GET
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Requires `jq`, which prints one name per line and reads the step file.
# - Confirmed directly: the answer is NOT an array and NOT {resultSet, result}: it is one object, {"charsets": [...]},
#   as the reference says. The lab lists 396 names, all different, sorted ignoring case (`Big5` first). It holds the
#   names the steps use (UTF-8, UTF-16, US-ASCII, ISO-8859-1, windows-1252) and the EBCDIC pages (IBM037, IBM1047).
# - Confirmed directly: the list is of the canonical names only, and is NOT what the server accepts. A route step
#   whose charset is not a charset the server's Java knows (`NOPE-9`) is refused, 400 "The charset specified by
#   inputCharset is not supported." (the same for outputCharset, on CharactersReplace, EncodingConversion,
#   LineEnding, LineFolding, LinePadding and LineTruncating); an empty one is 400 "The charset name specified by
#   inputCharset is illegal.". But `utf-8` (lower case), `UTF8` and `ASCII`, none of them in the list, are accepted
#   (201) and stored as written. So a name in the list is always accepted; a name outside it may be too. This script
#   compares exactly, as written, and says when the name differs from a listed one only in case.
# - Confirmed directly: the 11 step types that name no charset (Compress, Rename ...) ignore the list. Of the 17 steps
#   the 30.RouteStepsMetadata example prints with `minimal`, 6 types hold an inputCharset (UTF-8) and one,
#   EncodingConversion, an outputCharset (UTF-16); all are in the list: run `step FILE` on the output of that script.
# - Confirmed directly: the endpoint has no filter. name=, limit=, offset= and fields= are ignored and the whole list
#   is answered. HEAD is 200; POST, PUT, PATCH and DELETE are 405, /routeStepsCharsets/UTF-8 is 404, and
#   Accept: application/xml and text/csv are 406.
# - Exit codes: 0 when the name (or every charset in the file) is in the list, 1 when not, or when the server refuses,
#   2 for a wrong argument (nothing is sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routeStepsCharsets"
MODE="$1"
FILE="$2"

usage() {
    printf "Usage: 01.routeStepsCharsets_GET.sh [CHARSET | step FILE]\n"
    exit 2
}

if [ "${MODE}" = "step" ]; then
    if [ -z "${FILE}" ] || [ ! -f "${FILE}" ] || [ -n "$3" ]; then
        printf "step needs the name of a file that exists.\n"
        usage
    fi
    if ! jq -e . "${FILE}" > /dev/null 2>&1; then
        printf "%s is not JSON.\n" "${FILE}"
        exit 2
    fi
elif [ -n "${FILE}" ]; then
    usage
fi

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -w "\n%{http_code}")
CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${CODE}" != "200" ]; then
    printf "HTTP %s\n%s\n" "${CODE}" "${BODY}"
    exit 1
fi

LIST=$(printf "%s" "${BODY}" | jq -c '.charsets // []')

if [ "${MODE}" = "step" ]; then
    CHECKED=$(jq -r --argjson list "${LIST}" '
        (if type == "array" then . elif type == "object" and has("steps") then .steps else [.] end)
        | to_entries[] | .key as $i | select(.value | type == "object") | .value as $s
        | ("inputCharset", "outputCharset") as $f | select($s[$f] != null)
        | "  step \($i) \($s.type // "-") \($f) \($s[$f]): \(if ($list | map(. == $s[$f]) | any) then "listed" else "NOT listed" end)"' "${FILE}")
    if [ -z "${CHECKED}" ]; then
        printf "No inputCharset or outputCharset in %s: nothing to check.\n" "${FILE}"
        exit 0
    fi
    printf "%s\n" "${CHECKED}"
    if printf "%s\n" "${CHECKED}" | grep -q "NOT listed"; then
        exit 1
    fi
    exit 0
fi

if [ -n "${MODE}" ]; then
    if printf "%s" "${LIST}" | jq -e --arg c "${MODE}" 'index($c) != null' > /dev/null; then
        printf "%s is in the list.\n" "${MODE}"
        exit 0
    fi
    SAME=$(printf "%s" "${LIST}" | jq -r --arg c "${MODE}" 'map(select(ascii_downcase == ($c | ascii_downcase))) | first // empty')
    if [ -n "${SAME}" ]; then
        printf "%s is not in the list as written; the list has %s.\n" "${MODE}" "${SAME}"
    else
        printf "%s is not in the list.\n" "${MODE}"
    fi
    exit 1
fi

printf "Character sets: %s\n" "$(printf "%s" "${LIST}" | jq 'length')"
printf "%s" "${LIST}" | jq -r '.[] | "  " + .'
