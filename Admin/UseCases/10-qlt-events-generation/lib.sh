#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-11-09
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, ST_URL of the API 2.0, the cookie jar session.cookie.jar of this use case and st_session) and gives the
# helpers the steps share:
#
#   uc_get RESOURCE [NAME=VALUE ...]     GET of the API 2.0 with a session, the query made of the pairs, each encoded; sets LIST_CODE and LIST_BODY
#   uc_send METHOD RESOURCE JSON         PATCH, PUT or POST of the API 2.0 with a session and the csrfToken; sets LIST_CODE and LIST_BODY
#   uc_why                               prints why the server refused the call in LIST_BODY
#   uc_post RESOURCE JSON                POST that must answer 201; sets NEW_ID to the id at the end of the Location header; any other answer prints why and returns 1
#   uc_head RESOURCE / uc_delete RESOURCE   the status of a HEAD / of a DELETE of the API 2.0
#   uc_eu_folder NAME                    the End User API: the account makes a folder (an existing one is fine); prints the HTTP code
#   uc_upload FOLDER NAME                the End User API: the account uploads a small file, NAME, into FOLDER; prints the HTTP code
#   uc_eu_delete NAME                    the End User API: the account deletes a file; prints the HTTP code
#   uc_eu_files                          the End User API: the names of the regular files in the home folder of the account
#   uc_overflow_events FILE DEST         the End User API: the account downloads an overflow file of Sentinel; the events in it, one XML document a line, go to DEST; prints the HTTP code
#   uc_set_overflow FILE                 turns the overflow file of Sentinel to FILE (a name in the home folder of the account); sets LIST_CODE
#   uc_attr NAME                         reads one event (a line) on the standard input and prints the value of its attribute NAME
#   uc_kind                              reads one event on the standard input and prints its kind (XFBTransfer, AUDIT...)
#   uc_has_state EVENTS TEXT STATE       true when an event in the file EVENTS has the state STATE and holds TEXT (a file name, say)
#   uc_fake_lines / uc_fake_alive / uc_fake_stop    the fake HTTP server: the requests it logged so far; whether it runs; stop it (by its process id, after checking the command)
#   uc_fusion_add / uc_fusion_remove     the Fusion integration of the Send To Fusion step: make it, and put the Fusion options back as they were and compare them
#   uc_window                            the time at which the flow of the scenario started: the transfers of this run are the ones after it
#
# Settings it reads (from set_variables.local.sh, or the environment):
#   ST_CALLBACK_HOST   the address of THIS machine as the SecureTransport server sees it: the fake HTTP server listens here and the server connects to it (no default)
#   ST_CALLBACK_PORT   the port of the fake HTTP server (default 18081)
#   ST_ENDUSER_PORT    the End User port (default: the admin port minus one)
#
# The account of this use case is example_qlt. Its home folder holds the overflow files, one for each scenario, and the file the reads go to. The scenarios are in the folders 1-... and 2-...
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

ST_ENDUSER_PORT="${ST_ENDUSER_PORT:-$((ST_PORT - 1))}"
EU_URL="https://${ST_SERVER}:${ST_ENDUSER_PORT}/api/v2.0"
PASSWORD_FILE="${UC_DIR}/state.local.password"            # the password of the account (01 writes it, git ignores it)
SAVED_FILE="${UC_DIR}/state.local.sentinel.json"          # the Sentinel settings as they were before this use case (02 writes it, 99 puts them back)
FAKE_PID_FILE="${UC_DIR}/state.local.fake_server.pid"     # the process id of the fake HTTP server (04 writes it)
FAKE_LOG_FILE="${UC_DIR}/state.local.fake_server.log"     # what the fake HTTP server was sent, a line of JSON for each request
FUSION_FILE="${UC_DIR}/state.local.fusion.json"           # the Fusion options as they were before the Fusion integration was made (scenario 2 writes it)

ACCOUNT="example_qlt"
# The user id is fixed: a home folder keeps the uid of its first owner, and an account made again with another uid cannot write into it (403).
ACCOUNT_UID="41733"
READS_NAME="qlt_reads.dat"      # the overflow file while nothing is being recorded: the reads of the case files write their own events to it, not to the case file
FAKE_HOST="192.0.2.1"           # the Sentinel that cannot be reached: TEST-NET-1 (RFC 5737), reserved for documentation, never routed, so nothing can answer
FAKE_PORT="1305"                # the port Sentinel listens on by default
FAKE_SERVER_HOST="${ST_CALLBACK_HOST:-}"
FAKE_SERVER_PORT="${ST_CALLBACK_PORT:-18081}"
FUSION_NAME="example_qlt_fusion"
FUSION_USER="fusion-fake-user"          # the fake server does not check them: they only show in the Basic authentication it logs
FUSION_SECRET="fusion-fake-secret"

# Every state of a transfer the Sentinel settings can report (the reference of the Admin API, 5.5-20261029). The server may list more.
ALL_STATES=("ACKED" "AVAILABLE (ST_VAS)" "AVAILABLE (XFBTransfer)" "CANCELED" "DECRYPTED" "DECRYPTING" "DELETED" "ENCRYPTED" "ENCRYPTING" "ENDED_TO_ACK" "ERROR" "FAILED" "FORWARDED" "FORWARDING"
            "INTERRUPTED" "NACKED" "POST_PROC/ARCHIVED" "POST_PROC/ICAP_DENIED" "POST_PROC/ICAP_SCANNED" "POST_PROC/ICAP_SCANNING" "POST_PROC/ROUTED" "POST_PROC/ROUTING" "PRESERVED"
            "RECEIVED" "RECEIVING" "RENAMED" "ROUTED" "SENDING" "SENT" "SUBMITTED" "TO_EXECUTE" "TO_BE_DELETED" "WAITING" "LOGIN_START (AUDIT)" "LOGIN_END (AUDIT)" "FAILED (XFBRouting)"
            "POST_PROC/ROUTED (XFBRouting)")

uc_get() {
    local resource="$1" param result args=()
    shift
    for param in "$@"; do args+=(--data-urlencode "${param}"); done
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -G "${ST_URL}/${resource}" "${args[@]}" -H "accept: application/json" -H "Referer: ${REFERER}")
    LIST_CODE="${result: -3}"
    LIST_BODY="${result%???}"
}

uc_send() {      # METHOD RESOURCE JSON
    local result
    result=$(curl -k -s -w "%{http_code}" -b "${JAR}" -X "$1" "${ST_URL}/$2" -H "accept: application/json" -H "Referer: ${REFERER}" \
             -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$3")
    LIST_CODE="${result: -3}"
    LIST_BODY="${result%???}"
}

uc_why() {
    printf '%s' "${LIST_BODY}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${LIST_BODY}"
}

uc_post() {      # RESOURCE JSON: any other answer than 201 is a failure with the reason; the id of the new object is in NEW_ID
    local headers body code
    NEW_ID=""
    headers=$(mktemp); body=$(mktemp)
    code=$(curl -k -s -D "${headers}" -o "${body}" -w "%{http_code}" -b "${JAR}" -X POST "${ST_URL}/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
           -H "Content-Type: application/json" -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)" -d "$2")
    NEW_ID=$(tr -d '\r' < "${headers}" | sed -n 's/^[Ll]ocation: *//p' | sed 's|.*/||' | head -1)
    LIST_CODE="${code}"
    LIST_BODY=$(cat "${body}")
    rm -f "${headers}" "${body}"
    if [ "${code}" != "201" ]; then
        printf "POST /%s: HTTP %s\n" "$1" "${code}"
        uc_why
        return 1
    fi
    printf "  HTTP 201\n"
}

uc_head() {      # RESOURCE: the status of a HEAD
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" --head "${ST_URL}/$1" -H "accept: */*" -H "Referer: ${REFERER}"
}

uc_delete() {    # RESOURCE: the status of a DELETE
    curl -k -s -o /dev/null -w "%{http_code}" -b "${JAR}" -X DELETE "${ST_URL}/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "csrfToken: $(cat "${CSRF_FILE}" 2>/dev/null)"
}

uc_eu_folder() { # NAME: the status of making a folder (409 when it is there)
    curl -k -s -o /dev/null -w "%{http_code}" -u "${ACCOUNT}:$(cat "${PASSWORD_FILE}")" -X POST "${EU_URL}/files/$1" -H "accept: application/json" -H "Referer: ${REFERER}" \
        -H "Content-Type: application/json" -d '{"isDirectory": true, "isRegularFile": false, "isSymbolicLink": false, "isOther": false, "isShared": false}'
}

uc_upload() {    # FOLDER NAME: the status of the upload
    local local_file code
    local_file=$(mktemp)
    printf 'a small file, to make events of its transfers: %s\n' "$2" > "${local_file}"
    code=$(curl -k -s -o /dev/null -w "%{http_code}" -u "${ACCOUNT}:$(cat "${PASSWORD_FILE}")" -X POST "${EU_URL}/files/$1" -F "file=@${local_file};filename=$2" \
           -H "accept: application/json" -H "Referer: ${REFERER}")
    rm -f "${local_file}"
    printf '%s' "${code}"
}

uc_eu_delete() { # NAME: the status of the delete
    curl -k -s -o /dev/null -w "%{http_code}" -u "${ACCOUNT}:$(cat "${PASSWORD_FILE}")" -X DELETE "${EU_URL}/files/$1" -H "accept: application/json" -H "Referer: ${REFERER}"
}

uc_eu_files() {  # the names of the regular files in the home folder, one a line; nothing when the listing is refused
    local listing
    listing=$(curl -k -s -w "\n%{http_code}" -u "${ACCOUNT}:$(cat "${PASSWORD_FILE}")" "${EU_URL}/files" -H "accept: application/json" -H "Referer: ${REFERER}")
    [ "${listing##*$'\n'}" = "200" ] || return 1
    printf '%s' "${listing%$'\n'*}" | jq -r '(.files // [])[] | select(.isRegularFile) | .fileName'
}

uc_overflow_events() {   # FILE DEST: the events of an overflow file, one XML document a line
    local tmp code
    tmp=$(mktemp)
    code=$(curl -k -s -o "${tmp}" -w "%{http_code}" -u "${ACCOUNT}:$(cat "${PASSWORD_FILE}")" "${EU_URL}/files/$1" -H "accept: */*" -H "Referer: ${REFERER}")
    if [ "${code}" = "200" ]; then
        # Cut at each closing tag, not at each line: a record can follow the one before it with nothing between them (each is a length, a colon and the XML). What comes before the <?xml
        # of a part (the length, the padding, the header of the file) is dropped.
        LC_ALL=C tr '\r' '\n' < "${tmp}" | LC_ALL=C awk '{ n = split($0, parts, "</TrkDescriptor>"); for (i = 1; i < n; i++) { p = parts[i]; if (sub(/^.*<\?xml/, "<?xml", p)) print p "</TrkDescriptor>" } }' > "$2"
    fi
    rm -f "${tmp}"
    printf '%s' "${code}"
}

uc_set_overflow() {      # FILE: from now on the events that cannot be sent go to /home/ACCOUNT/FILE
    uc_send PATCH configurations/sentinel "$(jq -cn --arg path "/home/${ACCOUNT}/$1" '[{op: "replace", path: "/overflowFilePath", value: $path}]')"
}

uc_attr() {      # NAME: one event on the standard input
    LC_ALL=C grep -ao "<TrkAttr name=\"$1\" val=\"[^\"]*\"" | head -1 | LC_ALL=C sed 's/^.*val="//; s/"$//'
}

uc_kind() {      # one event on the standard input: the NAME of its TrkIdentifier (XFBTransfer, AUDIT...), or its type when it has no name (CycleLink: a transfer linked to the transfer it started)
    local identifier name
    identifier=$(LC_ALL=C grep -ao '<TrkIdentifier [^>]*' | head -1)
    name=$(printf '%s' "${identifier}" | LC_ALL=C sed -n 's/.* NAME="\([^"]*\)".*/\1/p')
    [ -n "${name}" ] || name=$(printf '%s' "${identifier}" | LC_ALL=C sed -n 's/.* type="\([^"]*\)".*/\1/p')
    printf '%s' "${name}"
}

uc_has_state() { # EVENTS TEXT STATE
    LC_ALL=C grep -aF "<TrkAttr name=\"STATE\" val=\"$3\"/>" "$1" | LC_ALL=C grep -aqF -- "$2"
}

# --- the fake HTTP server ----------------------------------------------------------------------------------------------------------------------------------
uc_fake_lines() {
    [ -f "${FAKE_LOG_FILE}" ] && wc -l < "${FAKE_LOG_FILE}" | tr -d ' ' || echo 0
}

uc_fake_pid() {  # the process id of our fake server when it runs, and nothing when it does not (or when the number is the one of another process)
    local pid
    pid=$(cat "${FAKE_PID_FILE}" 2>/dev/null)
    [ -n "${pid}" ] && ps -o command= -p "${pid}" 2>/dev/null | grep -qF "fake_http_server.py" && printf '%s' "${pid}"
}

uc_fake_alive() {
    [ -n "$(uc_fake_pid)" ]
}

uc_fake_stop() { # stop only the process this use case started: the id is checked against its command first
    local pid
    pid=$(uc_fake_pid)
    if [ -n "${pid}" ]; then
        kill "${pid}" 2>/dev/null
        echo "The fake HTTP server (process ${pid}) was stopped."
    else
        echo "The fake HTTP server was not running."
    fi
    rm -f "${FAKE_PID_FILE}"
}

# --- the Fusion integration ---------------------------------------------------------------------------------------------------------------------------------
uc_fusion_options() {    # every option of the Fusion integrations as {name: values}: LIST_CODE and LIST_BODY of the read, and the object on the standard output
    uc_get configurations/options "name=Fusion.Integrations*" "limit=200"
    [ "${LIST_CODE}" = "200" ] || return 1
    printf '%s' "${LIST_BODY}" | jq -S '[(.result // [])[] | {key: .name, value: .values}] | from_entries'
}

uc_fusion_add() {        # makes the integration FUSION_NAME, which posts to the fake server; keeps the Fusion options as they were in FUSION_FILE first
    local before registry
    before=$(uc_fusion_options) || { printf "GET /configurations/options: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; return 1; }
    [ -s "${FUSION_FILE}" ] || { umask 077; printf '%s\n' "${before}" > "${FUSION_FILE}"; }
    registry=$(printf '%s' "${before}" | jq -c --arg name "${FUSION_NAME}" '(.["Fusion.Integrations.Registry"] // []) | map(select(. != "")) | (if index($name) then . else . + [$name] end)')
    uc_send PUT configurations/options "$(jq -cn --argjson registry "${registry}" '[{name: "Fusion.Integrations.Registry", values: $registry}]')"
    if [ "${LIST_CODE}" != "204" ]; then printf "Adding the integration to the registry: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; return 1; fi
    uc_send PUT configurations/options "$(jq -cn --arg name "${FUSION_NAME}" --arg endpoint "http://${FAKE_SERVER_HOST}:${FAKE_SERVER_PORT}/fusion" --arg user "${FUSION_USER}" --arg secret "${FUSION_SECRET}" \
      '[["fusionEndpoint", $endpoint], ["authType", "BASIC"], ["dataSent", "ALL"], ["dataExpected", "PAYLOAD"], ["username", $user], ["password", $secret], ["verifyCertificate", "false"]]
       | map({name: ("Fusion.Integrations.Registry." + $name + "." + .[0]), values: [.[1]]})')"
    if [ "${LIST_CODE}" != "204" ]; then printf "Setting the integration: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; return 1; fi
    printf "  The Fusion integration %s posts to http://%s:%s/fusion, sends the file and its metadata, and expects the file back.\n" "${FUSION_NAME}" "${FAKE_SERVER_HOST}" "${FAKE_SERVER_PORT}"
}

uc_fusion_remove() {     # puts the registry back as it was, which deletes the options of the integration, and compares all the Fusion options with the copy; returns 1 when they differ
    local registry now
    [ -s "${FUSION_FILE}" ] || { echo "No Fusion integration was made by this use case: the Fusion options are as they were."; return 0; }
    registry=$(jq -c '(.["Fusion.Integrations.Registry"] // []) | (if length == 0 then [""] else . end)' "${FUSION_FILE}")
    uc_send PUT configurations/options "$(jq -cn --argjson registry "${registry}" '[{name: "Fusion.Integrations.Registry", values: $registry}]')"
    if [ "${LIST_CODE}" != "204" ]; then printf "Putting the Fusion registry back: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; return 1; fi
    now=$(uc_fusion_options) || { printf "GET /configurations/options: HTTP %s\n" "${LIST_CODE}"; return 1; }
    if [ "${now}" = "$(jq -S . "${FUSION_FILE}")" ]; then
        echo "The Fusion options read back are the same as before, key by key."
        rm -f "${FUSION_FILE}"
        return 0
    fi
    echo "The Fusion options read back differ from the copy (kept in $(basename "${FUSION_FILE}")):"
    jq -n --slurpfile saved "${FUSION_FILE}" --argjson now "${now}" '$saved[0] as $a | ($a | keys) + ($now | keys) | unique | map(select($a[.] != $now[.]))[]' | sed 's/^/  /'
    return 1
}

# BSD date (macOS) and GNU date (Linux) differ here.
if date -v-1d >/dev/null 2>&1; then
    uc_rfc_seconds_ago() { date -v-"$1"S -R; }
else
    uc_rfc_seconds_ago() { date -d "$1 seconds ago" -R; }
fi

uc_window() {    # the time at which the flow of the scenario started; empty when it has not run (WINDOW_FILE is set by the scenario)
    cat "${WINDOW_FILE}" 2>/dev/null
}
