#!/bin/bash
# ==============================================================================
# Script Name: 02.flow_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Step 2 of the scenario: run the flow, and record it. The overflow file of Sentinel is turned to the case file qlt_1_upload_push.dat, the account uploads a file, and the script waits until the route has finished
# (the fake server was sent 1 request and no event of the account is still active) and a few seconds more, then turns the overflow file away from the case file again.
# What the server reported in between is in the case file, and only that.
#
# Usage:
# ./02.flow_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from EndUser/UseCases/03-files-and-folders/02.files_POST_upload.sh (the upload, with Basic authentication) and Admin/API 2.0/bash/13.Configurations/19.configurations_sentinel_PATCH.sh (the overflow file).
# - A clean case file: one that an earlier run left is deleted first (the End User API can delete it), and the server makes it again when it writes the first event.
# - The file is turned to the reads file, qlt_reads.dat, before anything reads the case file: the reading makes events too (a login, a download), and they go to the reads file, not into the case file.
# - The uploaded file has a name of its own each time (push_<time>.txt): a file that was routed before is marked in-process by Advanced Routing for a while, and uploading it again is refused (403).
# - Do not delete the routes while a transfer of them is running: the server keeps the marker and the next upload is refused. This script waits for the end of the route; 99.objects_DELETE.sh is for after it.
# - It waits up to 2 minutes for the route, asking every 3 seconds, and then 10 seconds more: in the tried runs the last event of a transfer came up to 6 seconds after the others.
# - Whatever happens after the overflow file was turned to the case file, it is turned away again when the script ends.
# - Exit codes: 0 when the route finished, 1 when not (or a step before it failed).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./02.flow_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
scenario_flow
