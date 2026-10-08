#!/bin/bash
# ==============================================================================
# Script Name: 07.routes_POST_simple.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the five simple routes these examples use, using the `/routes`
# endpoint, one per scenario that has an outbound leg (scenario 2.1, only
# inbound, has no route at all):
#
#   2.2  one SendToPartner step, to the first partner
#   2.3  the SAME step twice: two SendToPartner steps, both to the first
#        partner, both reading the files the route itself was given rather than
#        each other's output, so the same file is pushed out twice
#   2.4  Compress, then one SendToPartner step reading the compressed step's
#        output
#   2.5  Decompress, then one SendToPartner step reading the decompressed
#        step's output (both files in one step, to the first partner)
#   2.6  Decompress, then a SendToPartner step to the first partner, then a
#        second SendToPartner step to the second partner - both reading the
#        decompressed files, since a push does not transform or consume them
#
# Usage:
# ./07.routes_POST_simple.sh
#
# Risk: write
#
# Notes:
# - Requires `jq`, which builds the JSON bodies.
# - A site is addressed as <site>#!#CVD#!# in transferSiteExpression - CVD is
#   part of the separator, not a name (see Features/trigger-route-after-
#   completed-pull, where this was confirmed against a real server).
# - usePrecedingStepFiles: false means "the files this route execution was
#   given", true means "the preceding step's own output". Both are documented
#   fields on SendToPartner itself.
# - Compress and Decompress step fields are from their own schema (not guessed):
#   Compress combines its inputs into one archive with singleArchiveEnabled,
#   named by singleArchiveName (not postTransformationActionRenameAsExpression,
#   which is a separate field - presumably for renaming the individual inputs
#   before they go into the archive, not the archive itself). Decompress needs
#   no rename field: the names inside the archive are kept. Neither has been
#   run against a real server yet.
# - The ids are saved as BT_ID_SIMPLE_2 to BT_ID_SIMPLE_6 for the later steps.
# - Stops at the first route the server refuses, and exits 1: run on its own, a
#   refused first route is not hidden by the ones after it.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

send_to_partner_step() {
    local site="$1" use_preceding="$2"
    jq -n --arg site "${site}" --argjson preceding "${use_preceding}" \
      '{type: "SendToPartner", status: "ENABLED", conditionType: "ALWAYS",
        autostart: false, usePrecedingStepFiles: $preceding,
        fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
        transferSiteExpressionType: "LIST",
        transferSiteExpression: ($site + "#!#CVD#!#"),
        actionOnStepFailure: "FAIL"}'
}

compress_step() {
    local archive_name="$1"
    jq -n --arg archive_name "${archive_name}" \
      '{type: "Compress", status: "ENABLED", conditionType: "ALWAYS",
        usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB",
        fileFilterExpression: "*", singleArchiveEnabled: true,
        compressionType: "ZIP", compressionLevel: "STORE",
        singleArchiveName: $archive_name, actionOnStepFailure: "FAIL"}'
}

decompress_step() {
    jq -n '{type: "Decompress", status: "ENABLED", conditionType: "ALWAYS",
            usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB",
            fileFilterExpression: "*", filenameCollisionResolutionType: "OVERWRITE",
            actionOnStepFailure: "FAIL"}'
}

create_simple_route() {
    local scenario="$1"; shift
    local name="${BT_SIMPLE_ROUTE_PREFIX}${scenario}"
    local steps body
    steps=$(jq -s '.' "$@")
    body=$(jq -n --arg name "${name}" --argjson steps "${steps}" \
      '{type: "SIMPLE", name: $name, conditionType: "ALWAYS", condition: true, steps: $steps}')

    printf "Creating the simple route %s...\n" "${name}"
    ar_admin_post "routes" "${body}" "BT_ID_SIMPLE_${scenario}"
}

W=$(mktemp -d)
trap 'rm -rf "${W}"' EXIT

send_to_partner_step "${BT_PUSH_SITE_1}" false > "${W}/s2_1.json"
create_simple_route 2 "${W}/s2_1.json" || exit 1

send_to_partner_step "${BT_PUSH_SITE_1}" false > "${W}/s3_1.json"
send_to_partner_step "${BT_PUSH_SITE_1}" false > "${W}/s3_2.json"
create_simple_route 3 "${W}/s3_1.json" "${W}/s3_2.json" || exit 1

compress_step "${BT_FILE_COMPRESSED_NAME}" > "${W}/s4_1.json"
send_to_partner_step "${BT_PUSH_SITE_1}" true > "${W}/s4_2.json"
create_simple_route 4 "${W}/s4_1.json" "${W}/s4_2.json" || exit 1

decompress_step > "${W}/s5_1.json"
send_to_partner_step "${BT_PUSH_SITE_1}" true > "${W}/s5_2.json"
create_simple_route 5 "${W}/s5_1.json" "${W}/s5_2.json" || exit 1

decompress_step > "${W}/s6_1.json"
send_to_partner_step "${BT_PUSH_SITE_1}" true > "${W}/s6_2.json"
send_to_partner_step "${BT_PUSH_SITE_2}" true > "${W}/s6_3.json"
create_simple_route 6 "${W}/s6_1.json" "${W}/s6_2.json" "${W}/s6_3.json" || exit 1
