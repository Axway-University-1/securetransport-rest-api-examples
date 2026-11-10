#!/bin/bash
# ==============================================================================
# Script Name: 01.objects_POST.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Step 1 of the scenario "Upload, and the server pushes to another server": make what the flow runs on. The account uploads a file. A subscription of the account to that folder runs an Advanced Routing route with ONE step, Send To Partner, which pushes the file to a Generic HTTP site: the fake HTTP server.
# The objects are named example_qlt_push_*; their ids are written down, as they are made, in state.local.objects.
#
# Usage:
# ./01.objects_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/06.TransferSites/01.sites_POST.sh (the site: a Generic HTTP one), 04.Applications/02.applications_POST.sh, 07.Subscriptions/02.subscriptions_POST.sh and 09.CompositeRoutes/02.compositeRoutes_POST.sh.
# - The site is of the type http-generic, not http: the plain HTTP site logs in, asks with HEAD for the folder and the file and expects a server of its own kind, while the Generic one sends the file with the
#   method and to the path it is given (here PUT /upload, a multipart form with the file in a part), which any server can take. Confirmed directly.
# - It needs ST_CALLBACK_HOST (the address of this machine as the server sees it, set in set_variables.local.sh), the account (../01), the copy of the Sentinel settings (../02).
# - The folder of the subscription is also made with the End User API (an existing one, 409, is fine): a file uploaded to a folder that is not there is not routed.
# - An existing set of objects (state.local.objects) is not made again: the script stops with exit 1. Remove it with 99.objects_DELETE.sh.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./01.objects_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
scenario_objects_create
