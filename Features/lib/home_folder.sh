#!/bin/bash
# ==============================================================================
# Script Name: home_folder.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# Shared across Features/, loaded by each feature's settings.sh, after enduser.sh.
# Finds out whether a new test account can use its home folder, and when it cannot,
# moves a run to the next free account name.
#
# Why: an account's home folder stays on disk, with its owner, when the account is
# deleted. A new account of that name with ANOTHER uid cannot create a folder
# directly in it: every such POST (and DELETE) is a 403 "Error occurred while creating
# file: null", while a folder below an existing one still works, which hides it.
# Confirmed on 5.5-20260924. Only a new account name gets a new home folder.
#
# - ar_home_probe ACCOUNT FOLDER
#       Logs in as ACCOUNT, makes the top-level folder FOLDER and removes it again.
#       Returns 0 when that works, 1 when the home is stale (a 403 "Error occurred
#       while creating file"), 2 when it could not tell (the login failed, or
#       another error: the example that makes the folders then reports it).
#       A nested folder would succeed and hide the problem: it is always top level.
# - ar_ensure_usable_home DEFAULT_NAME CURRENT_NAME PROBE_FOLDER
#       Probes CURRENT_NAME. On a stale home it deletes that Admin account (never a
#       partner: the caller passes only its own test account), takes the next name
#       that is free out of DEFAULT_NAME_2 .. DEFAULT_NAME_9, calls the caller's
#       ar_switch_account NEWNAME, and probes again. Returns 0 when the account in
#       AR_HOME_ACCOUNT is usable (or nothing could be told), 1 when it stopped:
#       every name up to _9 is stale or taken, the delete was refused, or
#       ar_switch_account failed. The caller ends with `|| exit 1`.
#
# The caller defines ar_switch_account NEWNAME: it makes NEWNAME the account of the
# rest of the run, and creates it. It returns 0 or 1.
#
# Notes:
# - Confirmed directly (5.5-20260924), on both features: a home folder left by an account of uid
#   1001 makes the probe of a new account of uid 41733 a 403 "Error occurred while creating file"
#   (the run moved to <name>_2 or _3 and went on to the end), and the probe of
#   a usable home succeeds. On a stale home, a GET or DELETE of a top-level folder that does not exist
#   is a 404, not a 403, so a cleanup can tell "not there" from "refused".
# - Needs ar_enduser_login, ar_enduser_call and ar_enduser_logout (enduser.sh),
#   ar_admin_delete and ar_admin_exists (admin_calls.sh) and jq.
# - Sets EU_ACCOUNT, as every login as another account does: the settings.sh of the
#   feature sets it again when it is sourced for the new name.
# ==============================================================================

ar_home_probe() {
    local account="$1" folder="$2" rc=2
    EU_ACCOUNT="${account}"
    ar_enduser_login >/dev/null || return 2
    ar_enduser_call POST "files/${folder}" "application/json" \
      "$(jq -n '{isDirectory: true, isRegularFile: false, isSymbolicLink: false, isOther: false, isShared: false}')"
    case "${AR_EU_CODE}" in
        2*)
            rc=0
            ar_enduser_call DELETE "files/${folder}" "" \
              || printf "The probe folder %s could not be removed from the home of %s (HTTP %s).\n" "${folder}" "${account}" "${AR_EU_CODE}"
            ;;
        403) [[ "${AR_EU_BODY}" == *"Error occurred while creating file"* ]] && rc=1 ;;
    esac
    ar_enduser_logout >/dev/null
    return "${rc}"
}

ar_ensure_usable_home() {
    local default="$1" account="$2" probe="$3" n=1 next
    AR_HOME_ACCOUNT="${account}"
    while true; do
        ar_home_probe "${AR_HOME_ACCOUNT}" "${probe}"
        [ $? -ne 1 ] && return 0
        n=$((n + 1))
        while [ "${n}" -le 9 ] && ar_admin_exists "accounts/${default}_${n}"; do
            n=$((n + 1))
        done
        if [ "${n}" -gt 9 ]; then
            printf "\nThe home folder of %s is left over from an earlier run, and so is every name up to %s_9\n" "${AR_HOME_ACCOUNT}" "${default}"
            printf "(or the account exists). Remove the old home folders, or run ./00.run_all.sh ANOTHER_NAME.\n"
            printf "Run ./99.cleanup_DELETE.sh %s to remove what this created.\n" "${AR_HOME_ACCOUNT}"
            return 1
        fi
        next="${default}_${n}"
        printf "\nThe home folder of %s is left over from an earlier run and belongs to another uid,\n" "${AR_HOME_ACCOUNT}"
        printf "so the account cannot create folders in it. A new name is used: %s.\n" "${next}"
        printf "Deleting the account %s (its home folder stays)...\n" "${AR_HOME_ACCOUNT}"
        if ! ar_admin_delete "accounts/${AR_HOME_ACCOUNT}"; then
            printf "The account %s could not be deleted, so the run stops here.\n" "${AR_HOME_ACCOUNT}"
            return 1
        fi
        AR_HOME_ACCOUNT="${next}"
        ar_switch_account "${next}" || return 1
    done
}
