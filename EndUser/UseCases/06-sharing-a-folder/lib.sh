#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-20
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the cookie jar session.cookie.jar of this use case, st_session and st_enc), and names what it works with.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# What this use case creates: one folder in the home folder, and one file in it.
# 99.cleanup_DELETE.sh removes exactly these names and nothing else.
FOLDER="example_uc_shared"
FILE_NAME="notes.txt"

# st_rights VALUE: the number of a type of share, from the number or the word: 1 or read, 3 or write (read and
# upload), 7 or full (read, upload and delete). Prints nothing for anything else.
st_rights() {
    case "$1" in
        1|read) echo 1 ;;
        3|write) echo 3 ;;
        7|full) echo 7 ;;
    esac
}

# st_rights_usage: what RIGHTS can be, for a usage message
st_rights_usage() {
    echo "  RIGHTS  what the other user may do: read (1), write (3: read and upload) or full (7: read, upload and delete)"
}

# st_session_note: said when the account has no e-mail address, or an administrator has just given it one
st_session_note() {
    echo "If an administrator has only just set the e-mail address, the session you are in does not know it yet: end the session with ./99.cleanup_DELETE.sh"
    echo "(it also removes what this use case made) and run this again, which logs in anew."
}
