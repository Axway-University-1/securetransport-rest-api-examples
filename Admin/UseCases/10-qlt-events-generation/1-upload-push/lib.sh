#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-11-10
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by the scripts of this folder: the scenario "Upload, and the server pushes to another server". It sets what makes the scenario its own (the tag of the names, the folder, the case file, whether the route has a Send To
# Fusion step, how many requests the fake server is sent) and loads ../lib.sh and ../scenario.sh, which hold the helpers and the steps.
#
# Usage:
# source lib.sh
#
# Risk: none
#
# Notes:
# - The case file is qlt_1_upload_push.dat, in the home folder of the account: the events of this scenario, and nothing else, are recorded in it.
# - upload -> route (Send To Partner) -> the fake server
# ==============================================================================

SCEN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCEN_DIR}/../lib.sh"
SCEN_TAG="push"
SCEN_FOLDER="qlt_push_in"
CASE_NAME="qlt_1_upload_push.dat"
SCEN_FUSION=0
SCEN_REQUESTS=1
SCEN_FINAL=""
source "${UC_DIR}/scenario.sh"
