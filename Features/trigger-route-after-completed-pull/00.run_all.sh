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
# ./00.run_all.sh [ACCOUNT] [--cleanup]
#
#   ACCOUNT      the test account to create and use (default arTestAccount)
#   --cleanup    the same, then run 99.cleanup_DELETE.sh at the end
#
# For example:
# ./00.run_all.sh                       run steps 01 to 13 and leave everything in place
# ./00.run_all.sh test_account          the same, with an account named test_account
# ./00.run_all.sh --cleanup             run steps 01 to 13, then remove everything again
# ./00.run_all.sh test_account --cleanup
#
# Risk: write
#
# Notes:
# - It stops at the first step that fails: a non-zero exit, or a line starting
#   HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing is cleaned up,
#   so you can look. Fix the problem, then run 99.cleanup_DELETE.sh and start again.
# - Needs settings.local.sh with AR_ACCOUNT_PASSWORD. See settings.sh.
# - After step 11 (the pull) and step 12 (the trigger file fix) it pauses
#   AR_STEP_PAUSE_SECONDS, 5 by default, so the pull and the route can run.
# - A stale home folder: an account's home folder stays on disk, with its owner,
#   when the account is deleted, and a new account with another uid cannot
#   create a folder directly in it (a 403 in step 04). So, only when no account
#   name was chosen (no ACCOUNT, no AR_RUN_ACCOUNT, no AR_TEST_ACCOUNT in
#   settings.local.sh), the run checks right after step 01 that the test account
#   can create a folder directly in its home (ar_home_probe, made and removed
#   again). If not, it says so, deletes that test account only, and moves to the
#   next free name: <default>_2, _3, up to _9. It stops after _9. The cleanup hint
#   and --cleanup use the name it ended on. A name you chose is never changed: step
#   04 then fails, with a hint.
# - The other objects (the sites, routes, application, subscription) keep their
#   names from settings.sh whatever the account is called, so run one account at a
#   time: a second run would meet the first one's names.
# - With --cleanup, the exit code of the run is the cleanup's: 1 when it could not remove
#   everything (it says what is left).
# - To run one step on its own, run its script directly.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"

usage() {
    printf "Usage: ./00.run_all.sh [ACCOUNT] [--cleanup]\n"
    exit 2
}

CLEANUP=0
POSITIONAL=()
for arg in "$@"; do
    case "${arg}" in
        --cleanup) CLEANUP=1 ;;
        -*)        usage ;;
        *)         POSITIONAL+=("${arg}") ;;
    esac
done
[ "${#POSITIONAL[@]}" -gt 1 ] && usage

if [ -n "${POSITIONAL[0]}" ]; then
    [[ "${POSITIONAL[0]}" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "${POSITIONAL[0]}"; exit 2; }
    export AR_RUN_ACCOUNT="${POSITIONAL[0]}"
fi

# Was an account name given on the command line or in the environment?
ACCOUNT_CHOSEN=0
[ -n "${AR_RUN_ACCOUNT}" ] && ACCOUNT_CHOSEN=1

# Loaded after the arguments, so settings.sh applies them, and every step this
# runs inherits them
source "${SCRIPT_DIR}/settings.sh"

# Was the account name chosen in settings.local.sh? Then it is never changed.
[ "${AR_TEST_ACCOUNT}" != "${AR_DEFAULT_ACCOUNT}" ] && ACCOUNT_CHOSEN=1

if [ -z "${AR_ACCOUNT_PASSWORD}" ]; then
    printf "AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# The command that removes what this run made: it names the account when that is
# not the default one
cleanup_command() {
    if [ "${AR_TEST_ACCOUNT}" = "${AR_DEFAULT_ACCOUNT}" ]; then
        printf "./99.cleanup_DELETE.sh"
    else
        printf "./99.cleanup_DELETE.sh %s" "${AR_TEST_ACCOUNT}"
    fi
}

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

# run_step STEP: runs one example; ends this script when it fails
run_step() {
    local step="$1" LOG RC
    LOG=$(mktemp)
    bash "${step}" 2>&1 | tee "${LOG}"
    RC=${PIPESTATUS[0]}
    if [ "${RC}" -ne 0 ] || grep -qE '^HTTP [45][0-9][0-9]' "${LOG}"; then
        rm -f "${LOG}"
        printf "\nStopped at step %s of %s: %s failed.\n" "${N}" "${TOTAL}" "$(basename "${step}")"
        printf "Nothing after it was run, and nothing was cleaned up.\n"
        printf "Fix it, run %s, and start again.\n" "$(cleanup_command)"
        exit 1
    fi
    rm -f "${LOG}"
}

# ar_switch_account NAME: called by ar_ensure_usable_home (Features/lib/home_folder.sh)
# when the home folder of the account is stale. The rest of this run, and everything
# it starts, uses NAME, and step 01 creates it.
ar_switch_account() {
    export AR_RUN_ACCOUNT="$1"
    source "${SCRIPT_DIR}/settings.sh"
    printf "\n--- again: 01.accounts_POST.sh for %s ---\n" "${AR_TEST_ACCOUNT}"
    run_step "${SCRIPT_DIR}/01.accounts_POST.sh"
}

for step in "${STEPS[@]}"; do
    N=$((N + 1))
    NAME=$(basename "${step}")
    printf "\n=== Step %s of %s: %s ===\n" "${N}" "${TOTAL}" "${NAME}"

    run_step "${step}"

    # The account exists now: can it create a folder in its home?
    case "${NAME}" in
        01.*)
            if [ "${ACCOUNT_CHOSEN}" -eq 0 ]; then
                ar_ensure_usable_home "${AR_DEFAULT_ACCOUNT}" "${AR_TEST_ACCOUNT}" "ar_home_probe" || exit 1
            fi
            ;;
    esac

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
    printf "Run %s to remove everything this created.\n" "$(cleanup_command)"
fi
