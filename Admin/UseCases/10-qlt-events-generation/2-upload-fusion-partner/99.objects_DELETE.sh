#!/bin/bash
# ==============================================================================
# Script Name: 99.objects_DELETE.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Removes what step 01 made: the routes, the subscription, the application, the site, and the events the account still has. For the scenario with Fusion it also puts the Fusion options back as they were
# and compares them. It is safe to run twice, and after a step that failed half way.
#
# Usage:
# ./99.objects_DELETE.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/09.CompositeRoutes/04.compositeRoutes_id_DELETE.sh and 07.Subscriptions/04.subscriptions_id_DELETE.sh.
# - It deletes by the ids written down in state.local.objects, never by a pattern.
# - The case file stays: it is the record of the scenario. ../99.cleanup_DELETE.sh deletes it with the other files of the account.
# - Exit codes: 0 when all is gone, 1 when something could not be deleted or the Fusion options are not the same afterwards.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./99.objects_DELETE.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
scenario_objects_delete
exit "${RC}"
