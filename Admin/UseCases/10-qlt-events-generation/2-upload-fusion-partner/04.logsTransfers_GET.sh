#!/bin/bash
# ==============================================================================
# Script Name: 04.logsTransfers_GET.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Step 4 of the scenario: tie the events to the transfers. Each event carries two ids of the transfer log: the coreId of the file and the localId of the transfer. The script reads the transfers of the
# account during the flow from the log, and for each prints the events of the case file that carry its coreId and those that carry its localId.
#
# Usage:
# ./04.logsTransfers_GET.sh
#
# Risk: read
#
# Notes:
# - Copied from Admin/API 2.0/bash/16.TransferLogs/01.logs_transfers_GET.sh, with the query of Admin/UseCases/09-resubmit-transfers.
# - It reads the events step 03 kept (state.local.events.txt), not the file again.
# - The transfers of the case file and of the reads file (the reading) are not listed.
# - Requires `jq`, which reads the log.
# - Exit codes: 0 when each transfer of the flow has events with its coreId, 1 when one has none or the log cannot be read, 2 when a parameter is given.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.logsTransfers_GET.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
scenario_log
