#!/bin/bash
# ==============================================================================
# Script Name: 00.run_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Runs the whole test, start to finish:
#
#   1. Prints the billable transfer count per day of the three accounts, today
#      and the six days before it (billable_GET_report.sh "before").
#   2. Sets up the three accounts, the sites, the folders, the application, the
#      routes and the subscriptions (01 to 09), uploads the sample files and
#      the two archives to partner_to_pull_from (10), and runs the six pulls
#      (11).
#   3. Prints the same report again (billable_GET_report.sh "after").
#   4. For each account, prints how many billable transfers this run added
#      today, next to what the rule predicts for it, and whether they match.
#
# Usage:
# ./00.run_all.sh [ACCOUNT [INBOUND_ONLY [IN_AND_OUT]]] [--cleanup]
#
#   ACCOUNT        the test account to create and use (default btTestAccount).
#                  Every other object name is derived from it.
#   INBOUND_ONLY   how many files scenario 2.1 (inbound only) runs (default 1)
#   IN_AND_OUT     how many files scenario 2.2 (inbound, then one outbound)
#                  runs (default 1)
#   --cleanup      after step 4, remove everything again (99)
#
# For example:
# ./00.run_all.sh                          defaults, leaves everything in place
# ./00.run_all.sh test_account             a test account named test_account
# ./00.run_all.sh test_account 6 12        and 6 inbound only, 12 in and out
# ./00.run_all.sh test_account 6 12 --cleanup
#
# Notes:
# - It stops at the first setup step that fails: a non-zero exit, or a line
#   starting HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing
#   is cleaned up, so you can look.
# - Needs settings.local.sh with BT_ACCOUNT_PASSWORD. See settings.sh.
# - The partners are shared by every test account. A run of another test
#   account on the same day, at the same time, adds to their counts too.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
usage() {
    printf "Usage: ./00.run_all.sh [ACCOUNT [INBOUND_ONLY [IN_AND_OUT]]] [--cleanup]\n"
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
[ "${#POSITIONAL[@]}" -gt 3 ] && usage

if [ -n "${POSITIONAL[0]}" ]; then
    [[ "${POSITIONAL[0]}" =~ ^[A-Za-z0-9._-]+$ ]] \
        || { printf "ACCOUNT may use only letters, digits, '.', '_' and '-': %s\n" "${POSITIONAL[0]}"; exit 2; }
    export BT_RUN_ACCOUNT="${POSITIONAL[0]}"
fi
for i in 1 2; do
    [ -z "${POSITIONAL[$i]}" ] && continue
    [[ "${POSITIONAL[$i]}" =~ ^[1-9][0-9]*$ ]] \
        || { printf "INBOUND_ONLY and IN_AND_OUT must be whole numbers, 1 or more: %s\n" "${POSITIONAL[$i]}"; exit 2; }
done
[ -n "${POSITIONAL[1]}" ] && export BT_RUN_INBOUND_ONLY="${POSITIONAL[1]}"
[ -n "${POSITIONAL[2]}" ] && export BT_RUN_IN_AND_OUT="${POSITIONAL[2]}"

# Loaded after the arguments, so settings.sh applies them, and every step this
# runs inherits them
source "${SCRIPT_DIR}/settings.sh"

printf "Account %s: scenario 2.1 with %s file(s), scenario 2.2 with %s file(s).\n" \
  "${BT_TEST_ACCOUNT}" "${BT_INBOUND_ONLY_COUNT}" "${BT_IN_AND_OUT_COUNT}"

if [ -z "${BT_ACCOUNT_PASSWORD}" ]; then
    printf "BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.sh to settings.local.sh and choose one.\n"
    exit 1
fi

# today_count LOG ACCOUNT: the TODAY_COUNT the report printed for an account
today_count() { sed -n "s/^TODAY_COUNT $2: //p" "$1"; }

printf "\n=== Step 1: billable transfers before this run ===\n"
REPORT_LOG=$(mktemp)
bash "${SCRIPT_DIR}/billable_GET_report.sh" "before" | tee "${REPORT_LOG}"
BEFORE_PULL=$(today_count "${REPORT_LOG}" "${BT_PULL_PARTNER}")
BEFORE_TEST=$(today_count "${REPORT_LOG}" "${BT_TEST_ACCOUNT}")
BEFORE_PUSH=$(today_count "${REPORT_LOG}" "${BT_PUSH_PARTNER}")
rm -f "${REPORT_LOG}"

# Every numbered setup step, except this script and the cleanup
STEPS=()
for f in "${SCRIPT_DIR}"/[0-9][0-9].*.sh; do
    case "$(basename "${f}")" in
        00.*|99.*) ;;
        *)         STEPS+=("${f}") ;;
    esac
done

TOTAL=${#STEPS[@]}
N=0
printf "\n=== Step 2: perform the transfers ===\n"
for step in "${STEPS[@]}"; do
    N=$((N + 1))
    NAME=$(basename "${step}")
    printf "\n--- %s of %s: %s ---\n" "${N}" "${TOTAL}" "${NAME}"

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

    # The pull (11) triggers routes and pushes that run asynchronously
    case "${NAME}" in
        11.*)
            printf "\nPausing %s seconds...\n" "${BT_STEP_PAUSE_SECONDS}"
            sleep "${BT_STEP_PAUSE_SECONDS}"
            ;;
    esac
done

bash "${SCRIPT_DIR}/12.files_GET_result.sh"

printf "\n=== Step 3: billable transfers after this run ===\n"
REPORT_LOG=$(mktemp)
bash "${SCRIPT_DIR}/billable_GET_report.sh" "after" | tee "${REPORT_LOG}"
AFTER_PULL=$(today_count "${REPORT_LOG}" "${BT_PULL_PARTNER}")
AFTER_TEST=$(today_count "${REPORT_LOG}" "${BT_TEST_ACCOUNT}")
AFTER_PUSH=$(today_count "${REPORT_LOG}" "${BT_PUSH_PARTNER}")
rm -f "${REPORT_LOG}"

# What the rule predicts each account adds. FILES is every file pulled: the
# inbound-only and in-and-out files, 1 for 2.3, 2 for 2.4, and one archive each
# for 2.5 and 2.6.
FILES=$((BT_INBOUND_ONLY_COUNT + BT_IN_AND_OUT_COUNT + 5))
#   partner_to_pull_from: each upload in is billable; each pull out is the
#     file's first outbound, so free
PREDICT_PULL=${FILES}
#   the test account: each pull in is billable; of the pushes out, the first in
#     each transfer chain (coreId) is free and the rest are billable. Decompress
#     keeps the archive's chain and Compress starts a new one (confirmed on a
#     real run), so: 2.3 one billable push, 2.5 one, 2.6 three of its four
PREDICT_TEST=$((FILES + 5))
#   partner_to_push_to: each push arriving is billable. 2.2 one per file, 2.3
#     two, 2.4 one archive, 2.5 two files, 2.6 two files to each of two folders
PREDICT_PUSH=$((BT_IN_AND_OUT_COUNT + 9))

printf "\n=== Step 4: analysis ===\n"
printf "The rule, from the Admin Guide: every inbound transfer is billable. For a\n"
printf "given file, the first outbound transfer that follows it is not billable;\n"
printf "every outbound transfer after that first one is.\n\n"
printf "Billable transfers this run added today, by account:\n\n"
printf "  %-24s %8s %8s %8s  %s\n" "account" "before" "after" "added" "the rule predicts"
MATCHED=1
analysis_row() {
    local account="$1" before="$2" after="$3" predicted="$4" added
    if [ -z "${before}" ] || [ -z "${after}" ]; then
        printf "  %-24s %8s %8s %8s  %s\n" "${account}" "${before:-?}" "${after:-?}" "?" "${predicted}"
        MATCHED=0
        return
    fi
    added=$((after - before))
    [ "${added}" -eq "${predicted}" ] || MATCHED=0
    printf "  %-24s %8s %8s %8s  %s%s\n" "${account}" "${before}" "${after}" "${added}" "${predicted}" \
      "$([ "${added}" -eq "${predicted}" ] && printf '' || printf '   differs')"
}
analysis_row "${BT_PULL_PARTNER}" "${BEFORE_PULL}" "${AFTER_PULL}" "${PREDICT_PULL}"
analysis_row "${BT_TEST_ACCOUNT}" "${BEFORE_TEST}" "${AFTER_TEST}" "${PREDICT_TEST}"
analysis_row "${BT_PUSH_PARTNER}" "${BEFORE_PUSH}" "${AFTER_PUSH}" "${PREDICT_PUSH}"

if [ "${MATCHED}" -eq 1 ]; then
    printf "\nEvery account added what the rule predicts.\n"
else
    printf "\nAn account did not add what the rule predicts, or its count could not be\n"
    printf "read. Read File Tracking for that account, grouped by Transfer name. A push\n"
    printf "still under way when step 3 ran shows up there, and in a later report.\n"
fi

if [ "${CLEANUP}" -eq 1 ]; then
    printf "\n=== Cleanup: 99.cleanup_DELETE.sh ===\n"
    bash "${SCRIPT_DIR}/99.cleanup_DELETE.sh"
else
    printf "\nRun ./99.cleanup_DELETE.sh %s to remove everything this created.\n" "${BT_TEST_ACCOUNT}"
fi
