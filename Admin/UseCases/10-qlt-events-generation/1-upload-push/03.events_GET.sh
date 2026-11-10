#!/bin/bash
# ==============================================================================
# Script Name: 03.events_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Step 3 of the scenario: read the events of the flow. The account downloads the case file qlt_1_upload_push.dat with the End User API and the script prints what is in it, in the order the server wrote it: when, which
# kind of event, which state, which direction, which file, and the coreId of its transfer, and then what the fake HTTP server was sent while the flow ran (state.local.requests.txt). With `raw` it also
# prints everything one event carries.
#
# Usage:
# ./03.events_GET.sh [raw]
#
# Risk: read
#
# Notes:
# - The kinds seen: XFBTransfer (a transfer: RECEIVING, RECEIVED, SENDING, SENT, TO_EXECUTE, POST_PROC, POST_PROC/ARCHIVED), XFBRouting (the route: POST_PROC), CycleLink (a transfer tied to the one it started) and AUDIT (a login).
# - The file is a circular buffer: a header line, then the events, each after a length and a colon, with a line break, a carriage return or nothing before it, then padding. The events are cut out at the
#   closing tag of each (see lib.sh).
# - It waits (up to a minute) until the file holds the RECEIVED event of the uploaded file and the SENT event of the last file the server sent. The reading is itself a transfer, with events, which go to
#   the reads file and not to the case file.
# - Needs curl, tr, grep, sed, awk and jq (for the requests of the fake server).
# - Exit codes: 0 when the events are there, 1 when not, 2 when the parameter is wrong (nothing sent).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./03.events_GET.sh [raw]"
if [ "$#" -gt 1 ] || { [ "$#" -eq 1 ] && [ "$1" != "raw" ]; }; then printf "%s\n" "${USAGE}"; exit 2; fi
scenario_events "$1"
