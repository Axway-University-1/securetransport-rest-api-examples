#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole feature, start to finish: every numbered example in this folder,
# in order, 01 to 13. It builds the test account, the sites, the routes and the
# subscription, puts sample files in place, runs the pull, fixes the trigger file,
# and shows what arrived in the delivered folder.
#
# Usage:
# ./00.run_all.sh              run steps 01 to 13 and leave everything in place
# ./00.run_all.sh --cleanup    the same, then run 99.cleanup_DELETE.sh at the end
#
# Notes:
# - It stops at the first step that fails: a non-zero exit, or a line starting
#   HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing is cleaned up,
#   so you can look. Fix the problem, then run 99.cleanup_DELETE.sh and start again.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - After step 11 (the pull) and step 12 (the trigger file fix) it pauses
#   AR_STEP_PAUSE_SECONDS, 5 by default, so the pull and the route can run.
# - To run one step on its own, run its script directly.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

CLEANUP=0
case "$1" in
    "")        ;;
    --cleanup) CLEANUP=1 ;;
    *)         printf "Usage: ./00.run_all.sh [--cleanup]\n"; exit 2 ;;
esac

if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
    printf "AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# Every numbered example except this script and the cleanup
STEPS=()
for f in "${SCRIPT_DIR}"/[0-9][0-9].*.sh; do
    case "$(basename "${f}")" in
        00.*|99.*) ;;
        *)         STEPS+=("${f}") ;;
    esac
done

TOTAL=${#STEPS[@]}
N=0
for step in "${STEPS[@]}"; do
    N=$((N + 1))
    NAME=$(basename "${step}")
    printf "\n=== Step %s of %s: %s ===\n" "${N}" "${TOTAL}" "${NAME}"

    LOG=$(mktemp)
    bash "${step}" 2>&1 | tee "${LOG}"
    RC=${PIPESTATUS[0]}

    if [ "${RC}" -ne 0 ] || grep -qE '^HTTP [45][0-9][0-9]' "${LOG}"; then
        rm -f "${LOG}"
        printf "\nStopped at step %s of %s: %s failed.\n" "${N}" "${TOTAL}" "${NAME}"
        printf "Nothing after it was run, and nothing was cleaned up.\n"
        printf "Fix it, run ./99.cleanup_DELETE.sh, and start again.\n"
        exit 1
    fi
    rm -f "${LOG}"

    # The pull and the route run asynchronously: after the pull (11) and after the
    # trigger file fix (12), give them a moment before the next step looks
    case "${NAME}" in
        11.*|12.*)
            printf "\nPausing %s seconds...\n" "${AR_STEP_PAUSE_SECONDS}"
            sleep "${AR_STEP_PAUSE_SECONDS}"
            ;;
    esac
done

printf "\nAll %s steps finished.\n" "${TOTAL}"

if [ "${CLEANUP}" -eq 1 ]; then
    printf "\n=== Cleanup: 99.cleanup_DELETE.sh ===\n"
    bash "${SCRIPT_DIR}/99.cleanup_DELETE.sh"
else
    printf "Run ./99.cleanup_DELETE.sh to remove everything this created.\n"
fi
