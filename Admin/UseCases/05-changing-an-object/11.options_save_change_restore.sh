#!/bin/bash
# ==============================================================================
# Script Name: 11.options_save_change_restore.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 11: a server setting. Save the option as it is (the whole answer), change it with PUT /configurations/options (a LIST of objects, each with name and values, and the values are a list of text), read
# it back, try the shapes the server refuses, and put the option back exactly. The last line compares the option now with the saved copy.
#
# Usage:
# ./11.options_save_change_restore.sh [OPTION] [VALUE]
#
#   OPTION  the option to change (default AddressBook.Limit.MaxDisplayEntries)
#   VALUE   the value to set while it is changed; it must differ from the value now (default 77)
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/13.Configurations/04.configurations_options_PUT.sh and 06.configurations_options_name_GET.sh. This is the one step that changes an object of the server that this use case did not make:
#   it saves the whole answer in state.local.option.json first, and 99.cleanup_DELETE.sh puts the option back from that file if this step was stopped half way.
# - It refuses to start when a saved copy is already there (an earlier run was stopped: run 99.cleanup_DELETE.sh first), and when the option is read only or does not exist.
# - A number in values ([78]) is stored as text; one object that is not in a list, and "value" in place of "values", are refused (400); an option that does not exist is 404; PATCH on this path is 405 (not tried here).
# - Exit 1 when the option is not back exactly as it was, or when a case does not come out as the README documents.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./11.options_save_change_restore.sh [OPTION] [VALUE]"
if [ "$#" -gt 2 ]; then printf "%s parameters were given, and at most 2 are taken: OPTION and VALUE.\n%s\n" "$#" "${USAGE}"; exit 2; fi
OPTION="${1:-${DEFAULT_OPTION}}"
VALUE="${2:-77}"
if [[ ! "${OPTION}" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf "OPTION is '%s': an option name holds letters, digits, '.', '_' and '-'.\n%s\n" "${OPTION}" "${USAGE}"
    exit 2
fi
st_session

if [ -s "${OPTION_FILE}" ]; then
    echo "There is a saved copy of an option from an earlier run ($(basename "${OPTION_FILE}")). Run 99.cleanup_DELETE.sh first: it puts the option back."
    exit 1
fi
SAVED=$(uc_option_read "${OPTION}")
if [ -z "${SAVED}" ]; then
    echo "There is no option ${OPTION} on this server. Nothing was changed."
    exit 1
fi
if [ "$(printf '%s' "${SAVED}" | jq '.readOnly')" = "true" ]; then
    echo "The option ${OPTION} is read only. Nothing was changed."
    exit 1
fi
if [ "$(printf '%s' "${SAVED}" | jq -c '.values')" = "$(jq -cn --arg v "${VALUE}" '[$v]')" ]; then
    echo "The option ${OPTION} already has the value ${VALUE}: give a VALUE that differs, so that the change can be seen. Nothing was changed."
    exit 1
fi
umask 077
printf '%s\n' "${SAVED}" > "${OPTION_FILE}"
echo "Saved: $(printf '%s' "${SAVED}" | jq -c '{name, values, defaultValues, specified, readOnly}')"

put_raw() {   # put_raw LABEL EXPECT_CODE BODY: a PUT of a body that is not the right shape, and that the option is not changed by it
    local result code
    printf '\n--- %s\n  body:    %s\n' "$1" "$3"
    result=$(curl -k -s -w "\n%{http_code}" -b "${JAR}" -X PUT "${ST_URL}/configurations/options" -H "accept: application/json" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$3")
    code="${result##*$'\n'}"
    printf '  answer:  HTTP %s\n' "${code}"
    printf '%s\n' "$(printf '%s' "${result%$'\n'*}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s' "${result%$'\n'*}")" | sed 's/^/           /'
    printf '  values:  %s\n' "$(uc_option_read "${OPTION}" | jq -c .values)"
    if [ "${code}" != "$2" ]; then
        printf '  NOT AS DOCUMENTED: this use case expects HTTP %s. The server answered HTTP %s.\n' "$2" "${code}"
        UC_FAILED=1
    fi
}

echo
echo "--- change it: a list of objects, each with name and values (a list of text)"
code=$(uc_option_put "${OPTION}" "$(jq -cn --arg v "${VALUE}" '[$v]')")
echo "  answer:  HTTP ${code}"
NOW=$(uc_option_read "${OPTION}" | jq -c .values)
echo "  values:  ${NOW}"
if [ "${code}" != "204" ] || [ "${NOW}" != "$(jq -cn --arg v "${VALUE}" '[$v]')" ]; then
    echo "  The change did not take. Putting the option back."
    UC_FAILED=1
else
    put_raw "'value' where 'values' belongs" 400 "$(jq -cn --arg n "${OPTION}" --arg v "${VALUE}" '[{name: $n, value: $v}]')"
    put_raw "one object, not a list of objects" 400 "$(jq -cn --arg n "${OPTION}" --arg v "${VALUE}" '{name: $n, values: [$v]}')"
    put_raw "an option that does not exist" 404 '[{"name":"No.Such.Option","values":["1"]}]'
fi

echo
echo "--- put it back: the values of the saved copy"
code=$(uc_option_put "${OPTION}" "$(printf '%s' "${SAVED}" | jq -c .values)")
echo "  answer:  HTTP ${code}"
BACK=$(uc_option_read "${OPTION}")
if [ "${code}" = "204" ] && [ "$(printf '%s' "${BACK}" | jq -S -c .)" = "$(printf '%s' "${SAVED}" | jq -S -c .)" ]; then
    echo "  The option ${OPTION} is as it was: the answer now is the same, field for field, as the copy that was saved."
    rm -f "${OPTION_FILE}"
elif [ "${code}" = "204" ] && [ "$(printf '%s' "${BACK}" | jq -c .values)" = "$(printf '%s' "${SAVED}" | jq -c .values)" ]; then
    echo "  The values are back. These fields differ from the saved copy: $(jq -n -r --argjson a "${SAVED}" --argjson b "${BACK}" '[$a | keys[] | select($a[.] != $b[.])] | join(", ")')"
    echo "  (an option that was not specified is specified now, with the value it had.)"
    rm -f "${OPTION_FILE}"
else
    echo "  The option is NOT back as it was. The saved copy stays in $(basename "${OPTION_FILE}"): run 99.cleanup_DELETE.sh to try again, or set ${OPTION} by hand."
    exit 1
fi
uc_done
