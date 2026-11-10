#!/bin/bash
# ==============================================================================
# Script Name: scenario.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by the lib.sh of each scenario folder (1-upload-push, 2-upload-fusion-partner), which sets what makes the scenario its own:
#
#   SCEN_TAG       a short name, in the names of the objects and of the uploaded file (push, fusion)
#   SCEN_FOLDER    the folder of the account the subscription watches
#   CASE_NAME      the overflow file of the scenario: the events of its flow, and nothing else, are recorded in it
#   SCEN_FUSION    1 when the route has a Send To Fusion step first, 0 for the Send To Partner step alone
#   SCEN_REQUESTS  how many requests the fake HTTP server is sent by one flow (1: the file; 2: Fusion, then the file)
#   SCEN_FINAL     the text that tells the last file the server sends: the uploaded file itself, or the file Fusion sent back
#
# and gives the steps of a scenario, each of which is a thin script:
#
#   scenario_objects_create    01: the site, the application, the subscription and the routes (and the Fusion integration), and the folder
#   scenario_flow              02: record into the case file, upload, wait for the route to finish, stop recording
#   scenario_events [raw]      03: read the case file and print its events and what the fake server was sent
#   scenario_log               04: tie the events to the transfers of the transfer log
#   scenario_objects_delete    99: take it all away again, and put the Fusion options back
#
# Why a file of its own: the events of a scenario are the ones in its overflow file. The server writes to ONE overflow file at a time, so the flow is run with the overflow file turned to the
# case file, and the file is turned away again before the case file is read. The reading, which makes events too (a login and a download), then writes to the reads file, not to the case file.
#
# Usage:
# source scenario.sh
#
# Risk: none
# ==============================================================================

OBJECTS_FILE="${SCEN_DIR}/state.local.objects"        # the ids of the objects made, one name=id a line
WINDOW_FILE="${SCEN_DIR}/state.local.window"          # the time at which the flow started
UPLOAD_FILE="${SCEN_DIR}/state.local.upload"          # the name of the file the flow uploaded
EVENTS_FILE="${SCEN_DIR}/state.local.events.txt"      # the events of the case file, one XML document a line
REQUESTS_FILE="${SCEN_DIR}/state.local.requests.txt"  # what the fake server was sent during the flow, a line of JSON for each request

SITE_NAME="example_qlt_${SCEN_TAG}_site"
APP_NAME="example_qlt_${SCEN_TAG}_app"
TEMPLATE_NAME="example_qlt_${SCEN_TAG}_template"
SIMPLE_NAME="example_qlt_${SCEN_TAG}_simple"
COMPOSITE_NAME="example_qlt_${SCEN_TAG}_composite"

scenario_need() {   # the files the scenario needs; exits 1 with what to run first
    local what
    for what in "$@"; do
        case "${what}" in
            password) [ -s "${PASSWORD_FILE}" ] || { echo "There is no password for the account: run ../01.accounts_POST.sh first."; exit 1; } ;;
            copy) [ -s "${SAVED_FILE}" ] || { echo "The Sentinel settings are not kept: run ../02.sentinel_GET.sh first. Nothing was changed."; exit 1; } ;;
            host) [ -n "${FAKE_SERVER_HOST}" ] || { echo "ST_CALLBACK_HOST is not set: it is the address of THIS machine as the SecureTransport server reaches it (the fake HTTP server runs here). Add it to set_variables.local.sh."; exit 1; } ;;
            objects) [ -s "${OBJECTS_FILE}" ] || { echo "The objects of this scenario are not made: run 01.objects_POST.sh first."; exit 1; } ;;
            fake) uc_fake_alive || { echo "The fake HTTP server is not running: run ../04.fakeServer_start.sh first."; exit 1; } ;;
            flow) [ -s "${UPLOAD_FILE}" ] && [ -n "$(uc_window)" ] || { echo "The flow was not run: run 02.flow_POST.sh first."; exit 1; } ;;
        esac
    done
}

scenario_remember() {   # NAME ID: write down an object that was made, at once, so that 99 can take it away whatever happens next
    printf '%s=%s\n' "$1" "$2" >> "${OBJECTS_FILE}"
}

scenario_id() {         # NAME: the id written down for it
    sed -n "s/^$1=//p" "${OBJECTS_FILE}" 2>/dev/null | head -1
}

scenario_objects_create() {
    scenario_need password copy host
    if [ -s "${OBJECTS_FILE}" ]; then echo "The objects of this scenario are made already (see $(basename "${OBJECTS_FILE}")). Remove them with 99.objects_DELETE.sh."; exit 1; fi
    st_session

    if [ "${SCEN_FUSION}" = "1" ]; then
        echo "Making the Fusion integration ${FUSION_NAME}..."
        uc_fusion_add || exit 1
    fi
    echo "Making the Generic HTTP site ${SITE_NAME}, which pushes to the fake server at ${FAKE_SERVER_HOST}:${FAKE_SERVER_PORT}..."
    uc_post sites "$(jq -cn --arg name "${SITE_NAME}" --arg account "${ACCOUNT}" --arg host "${FAKE_SERVER_HOST}" --argjson port "${FAKE_SERVER_PORT}" \
      '{type: "http-generic", protocol: "http-generic", name: $name, account: $account, transferType: "partner", ghttpHost: $host, ghttpPort: $port, ghttpNetworkZone: "none",
        ghttpUploadUrlPath: "/upload", ghttpUploadMethod: "PUT"}')" || exit 1
    scenario_remember site "${NEW_ID}"

    echo "Making the Advanced Routing application ${APP_NAME} and the subscription of ${ACCOUNT} to the folder /${SCEN_FOLDER}..."
    uc_post applications "$(jq -cn --arg name "${APP_NAME}" '{type: "AdvancedRouting", name: $name}')" || exit 1
    scenario_remember application "${APP_NAME}"
    uc_post subscriptions "$(jq -cn --arg account "${ACCOUNT}" --arg app "${APP_NAME}" --arg folder "/${SCEN_FOLDER}" '{type: "AdvancedRouting", account: $account, application: $app, folder: $folder}')" || exit 1
    scenario_remember subscription "${NEW_ID}"
    SUBSCRIPTION_ID="${NEW_ID}"

    echo "Making the routes: the template, the simple route with its steps, and the composite route that puts them on the subscription..."
    uc_post routes "$(jq -cn --arg name "${TEMPLATE_NAME}" '{name: $name, description: "QLT events use case", type: "TEMPLATE", conditionType: "MATCH_ALL"}')" || exit 1
    scenario_remember template "${NEW_ID}"
    TEMPLATE_ID="${NEW_ID}"
    uc_post routes "$(jq -cn --arg name "${SIMPLE_NAME}" --arg site "${SITE_NAME}" --arg fusion "${FUSION_NAME}" --argjson withFusion "${SCEN_FUSION}" '
      def partner($previous): {type: "SendToPartner", status: "ENABLED", conditionType: "ALWAYS", autostart: false, usePrecedingStepFiles: $previous, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
                               transferSiteExpressionType: "LIST", transferSiteExpression: ($site + "#!#CVD#!#"), actionOnStepFailure: "FAIL"};
      def fusionStep: {type: "SendToFusion", status: "ENABLED", conditionType: "ALWAYS", autostart: false, fusionIntegrationName: $fusion, fileFilterExpressionType: "GLOB", fileFilterExpression: "*", actionOnStepFailure: "FAIL"};
      {type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true, steps: (if $withFusion == 1 then [fusionStep, partner(true)] else [partner(false)] end)}')" || exit 1
    scenario_remember simple "${NEW_ID}"
    SIMPLE_ID="${NEW_ID}"
    uc_post routes "$(jq -cn --arg name "${COMPOSITE_NAME}" --arg account "${ACCOUNT}" --arg template "${TEMPLATE_ID}" --arg subscription "${SUBSCRIPTION_ID}" --arg simple "${SIMPLE_ID}" \
      '{type: "COMPOSITE", account: $account, name: $name, conditionType: "MATCH_ALL", routeTemplate: $template, subscriptions: [$subscription],
        steps: [{type: "ExecuteRoute", status: "ENABLED", autostart: false, executeRoute: $simple}]}')" || exit 1
    scenario_remember composite "${NEW_ID}"

    code=$(uc_eu_folder "${SCEN_FOLDER}")
    case "${code}" in
        201|409) echo "The folder /${SCEN_FOLDER} of ${ACCOUNT} is there." ;;
        000) echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1 ;;
        *) echo "Making the folder /${SCEN_FOLDER}: HTTP ${code}"; exit 1 ;;
    esac
}

scenario_flow() {
    scenario_need password copy objects fake
    st_session

    code=$(uc_eu_delete "${CASE_NAME}")
    case "${code}" in
        204) echo "The overflow file of an earlier run, ${CASE_NAME}, was deleted: the case file starts clean." ;;
        404) ;;
        000) echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1 ;;
        *) echo "Deleting ${CASE_NAME}: HTTP ${code}"; exit 1 ;;
    esac

    local before upload_name seen events waited
    FLOW_RECORDING=""
    before=$(uc_fake_lines)
    uc_rfc_seconds_ago 2 > "${WINDOW_FILE}"
    turn_away() {
        [ -n "${FLOW_RECORDING}" ] || return 0
        uc_set_overflow "${READS_NAME}"
        if [ "${LIST_CODE}" = "204" ]; then echo "The overflow file is ${READS_NAME} again: what is read from now on is not recorded in ${CASE_NAME}."; FLOW_RECORDING=""
        else printf "Turning the overflow file back to %s: HTTP %s: %s\n" "${READS_NAME}" "${LIST_CODE}" "$(uc_why)"; fi
    }
    trap turn_away EXIT

    uc_set_overflow "${CASE_NAME}"
    if [ "${LIST_CODE}" != "204" ]; then printf "Turning the overflow file to %s: HTTP %s: %s\n" "${CASE_NAME}" "${LIST_CODE}" "$(uc_why)"; exit 1; fi
    FLOW_RECORDING=1
    echo "Recording: the overflow file is ${CASE_NAME}. Every event of the server from now on goes to it."

    upload_name="${SCEN_TAG}_$(date +%s).txt"
    printf '%s\n' "${upload_name}" > "${UPLOAD_FILE}"
    code=$(uc_upload "${SCEN_FOLDER}" "${upload_name}")
    if [ "${code}" = "000" ]; then echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1; fi
    if [[ "${code}" != 20* ]]; then echo "${ACCOUNT} uploads ${upload_name} to /${SCEN_FOLDER}: HTTP ${code}"; exit 1; fi
    echo "${ACCOUNT} uploaded ${upload_name} to /${SCEN_FOLDER} (HTTP ${code}). The route runs; waiting for it to finish (up to 2 minutes)..."

    waited=0
    for attempt in $(seq 1 40); do
        sleep 3
        waited=$((attempt * 3))
        seen=$(( $(uc_fake_lines) - before ))
        uc_get events "accountName=${ACCOUNT}" "limit=5"
        events=$(printf '%s' "${LIST_BODY}" | jq -r '(.result // []) | length' 2>/dev/null)
        printf "  after %s s: the fake server was sent %s of %s requests, %s events of the account still active\n" "${waited}" "${seen}" "${SCEN_REQUESTS}" "${events:-?}"
        if [ "${seen}" -ge "${SCEN_REQUESTS}" ] && [ "${events:-1}" = "0" ]; then break; fi
    done
    if [ "${seen}" -lt "${SCEN_REQUESTS}" ]; then
        echo "The fake server was sent only ${seen} of ${SCEN_REQUESTS} requests. Does the SecureTransport server reach ${FAKE_SERVER_HOST}:${FAKE_SERVER_PORT}? (ST_CALLBACK_HOST must be the address of this machine as the server sees it.)"
        exit 1
    fi
    echo "The route finished. Waiting 10 seconds more: the last events of a transfer can come a few seconds after it."
    sleep 10
    turn_away
    trap - EXIT
    [ -z "${FLOW_RECORDING}" ] || exit 1
    sed -n "$((before + 1)),\$p" "${FAKE_LOG_FILE}" > "${REQUESTS_FILE}"
}

scenario_events() {   # [raw]
    scenario_need password flow
    local raw="$1" name ready="" attempt code events kind
    name=$(cat "${UPLOAD_FILE}")

    echo "Reading ${CASE_NAME} as ${ACCOUNT} (up to 1 minute)..."
    for attempt in $(seq 1 12); do
        code=$(uc_overflow_events "${CASE_NAME}" "${EVENTS_FILE}")
        case "${code}" in
            200) if uc_has_state "${EVENTS_FILE}" "${name}" RECEIVED && uc_has_state "${EVENTS_FILE}" "${SCEN_FINAL:-${name}}" SENT; then ready=1; break; fi
                 printf "  %s events in the file, the end of the flow is not there yet\n" "$(wc -l < "${EVENTS_FILE}" | tr -d ' ')" ;;
            404) echo "  ${CASE_NAME} is not there. Did 02.flow_POST.sh run, and was the overflow file turned to it?"; exit 1 ;;
            000) echo "No answer from ${ST_SERVER}:${ST_ENDUSER_PORT}. The End User API has its own port: set ST_ENDUSER_PORT in set_variables.local.sh."; exit 1 ;;
            *) echo "Downloading ${CASE_NAME}: HTTP ${code}"; exit 1 ;;
        esac
        sleep 5
    done
    if [ -z "${ready}" ]; then echo "The file does not hold the RECEIVED event of ${name} and the SENT event of the last file after a minute."; exit 1; fi

    printf '\nThe case file %s holds %s events: everything the server reported while the flow ran.\n\n' "${CASE_NAME}" "$(wc -l < "${EVENTS_FILE}" | tr -d ' ')"
    printf '  %-9s %-13s %-24s %-3s %-44s %s\n' "TIME" "EVENT" "STATE / ACTION" "DIR" "FILE / USER" "COREID"
    while IFS= read -r event; do
        [ -n "${event}" ] || continue
        kind=$(printf '%s' "${event}" | uc_kind)
        file=$(printf '%s' "${event}" | uc_attr PROTOCOLFILENAME)
        [ -n "${file}" ] || file=$(printf '%s' "${event}" | uc_attr FILENAME | sed 's|.*/||')
        [ -n "${file}" ] || file=$(printf '%s' "${event}" | uc_attr LOGINNAME)
        state=$(printf '%s' "${event}" | uc_attr STATE)
        [ "${kind}" != "AUDIT" ] || state=$(printf '%s' "${event}" | uc_attr ACTION)
        if [ "${kind}" = "CycleLink" ]; then
            state="$(printf '%s' "${event}" | uc_attr PARENTOBJECT) -> $(printf '%s' "${event}" | uc_attr CHILDOBJECT)"
            file="cycle $(printf '%s' "${event}" | uc_attr PARENTCYCLEID | cut -c1-6) -> $(printf '%s' "${event}" | uc_attr CHILDCYCLEID | cut -c1-6)"
        fi
        printf '  %-9s %-13s %-24s %-3s %-44s %s\n' "$(printf '%s' "${event}" | uc_attr EVENTTIME)" "${kind:-?}" "${state}" "$(printf '%s' "${event}" | uc_attr DIRECTION)" "${file:0:44}" \
            "$(printf '%s' "${event}" | uc_attr COREID | cut -c1-8)"
    done < "${EVENTS_FILE}"
    printf '\n  Kinds:'
    while IFS= read -r event; do printf '%s\n' "$(printf '%s' "${event}" | uc_kind)"; done < "${EVENTS_FILE}" | sort | uniq -c | awk '{ printf " %s %s,", $1, $2 }' | sed 's/,$//'
    printf '\n  DIR R is a file received, S a file sent. COREID is the id of the file in the transfer log: step 04. A CycleLink ties a transfer to the one it started (the upload to its push).\n'

    printf '\nWhat the fake HTTP server was sent while the flow ran:\n\n'
    jq -r '"  \(.t)  \(.method) \(.path)  \(.bytes) bytes  the file \(.file // "-")  answered \(.answer)"' "${REQUESTS_FILE}" 2>/dev/null || echo "  (nothing was kept)"

    if [ "${raw}" = "raw" ]; then
        printf '\nEverything the RECEIVED event of %s carries (the attributes that have a value):\n\n' "${name}"
        LC_ALL=C grep -aF '<TrkAttr name="STATE" val="RECEIVED"/>' "${EVENTS_FILE}" | LC_ALL=C grep -aF -- "${name}" | head -1 \
            | LC_ALL=C grep -ao '<TrkAttr name="[^"]*" val="[^"]*"' | LC_ALL=C sed 's/^<TrkAttr name="//; s/" val="/ /; s/"$//' | LC_ALL=C sort | awk '{ printf "  %-22s %s\n", $1, substr($0, length($1) + 2) }'
    fi
}

scenario_log() {
    scenario_need password flow
    [ -s "${EVENTS_FILE}" ] || { echo "There are no events: run 03.events_GET.sh first."; exit 1; }
    st_session
    uc_get logs/transfers "account=${ACCOUNT}" "startTimeAfter=$(uc_window)" "limit=100"
    if [ "${LIST_CODE}" != "200" ]; then printf "GET /logs/transfers: HTTP %s: %s\n" "${LIST_CODE}" "$(uc_why)"; exit 1; fi

    local rc=0 found=0 file core localid status by_core by_local event
    echo "The transfers of ${ACCOUNT} in the transfer log during the flow (after $(uc_window)), and the events that carry their ids:"
    while IFS=$'\t' read -r file core localid status; do
        [ -n "${file}" ] || continue
        found=$((found + 1))
        by_core=""; by_local=""
        while IFS= read -r event; do
            [ -n "${event}" ] || continue
            by_core="${by_core} $(printf '%s' "${event}" | uc_attr STATE)"
        done <<< "$(LC_ALL=C grep -aF "<TrkAttr name=\"COREID\" val=\"${core}\"/>" "${EVENTS_FILE}")"
        while IFS= read -r event; do
            [ -n "${event}" ] || continue
            by_local="${by_local} $(printf '%s' "${event}" | uc_attr STATE)"
        done <<< "$(LC_ALL=C grep -aF "<TrkAttr name=\"LOCALID\" val=\"${localid}\"/>" "${EVENTS_FILE}")"
        printf '\n  %s (%s)\n    coreId  %s\n    localId %s\n    events with this coreId:  %s\n    events with this localId: %s\n' "${file}" "${status}" "${core}" "${localid}" "${by_core# }" "${by_local# }"
        if [ -z "${by_core}" ]; then rc=1; echo "    no event carries this coreId"; fi
    done < <(printf '%s' "${LIST_BODY}" | jq -r --arg reads "${READS_NAME}" --arg case "${CASE_NAME}" \
        '(.result // []) | reverse | .[] | (.filename // .fileName // "") as $f | select($f != $reads and $f != $case and $f != "") | [$f, .coreId, .id.mTransferStatusId, .status] | @tsv')
    if [ "${found}" -eq 0 ]; then echo "  The log shows no transfer of the flow: has the log caught up?"; exit 1; fi
    printf '\n'
    if [ "${rc}" -eq 0 ]; then echo "Every transfer of the flow in the log has events that carry its coreId."; fi
    exit "${rc}"
}

scenario_objects_delete() {
    local id ids code
    RC=0
    st_session
    for name in composite simple template; do
        id=$(scenario_id "${name}")
        [ -n "${id}" ] || continue
        code=$(uc_delete "routes/${id}")
        case "${code}" in 204) echo "The ${name} route was deleted." ;; 404|400) echo "The ${name} route was not there." ;; *) echo "The ${name} route could not be deleted (HTTP ${code})."; RC=1 ;; esac
    done
    id=$(scenario_id subscription)
    if [ -n "${id}" ]; then
        code=$(uc_delete "subscriptions/${id}")
        case "${code}" in 204) echo "The subscription was deleted." ;; 404|400) echo "The subscription was not there." ;; *) echo "The subscription could not be deleted (HTTP ${code})."; RC=1 ;; esac
    fi
    if [ -n "$(scenario_id application)" ]; then
        code=$(uc_delete "applications/${APP_NAME}")
        case "${code}" in 204) echo "The application ${APP_NAME} was deleted." ;; 404|400) echo "The application was not there." ;; *) echo "The application could not be deleted (HTTP ${code})."; RC=1 ;; esac
    fi
    id=$(scenario_id site)
    if [ -n "${id}" ]; then
        code=$(uc_delete "sites/${id}")
        case "${code}" in 204) echo "The site ${SITE_NAME} was deleted." ;; 404|400) echo "The site was not there." ;; *) echo "The site could not be deleted (HTTP ${code})."; RC=1 ;; esac
    fi
    # an event a route left behind would keep retrying: only the ones of this account are deleted
    uc_get events "accountName=${ACCOUNT}" "limit=100"
    ids=$(printf '%s' "${LIST_BODY}" | jq -c '[(.result // [])[] | .id]' 2>/dev/null)
    if [ -n "${ids}" ] && [ "${ids}" != "[]" ]; then
        uc_send POST "events/operations?operation=delete" "$(jq -cn --argjson ids "${ids}" '{ids: $ids}')"
        echo "Events of ${ACCOUNT} that were still there were deleted (HTTP ${LIST_CODE})."
    fi
    if [ "${SCEN_FUSION}" = "1" ]; then
        uc_fusion_remove || RC=1
    fi
    rm -f "${OBJECTS_FILE}" "${WINDOW_FILE}" "${UPLOAD_FILE}" "${EVENTS_FILE}" "${REQUESTS_FILE}"
}
