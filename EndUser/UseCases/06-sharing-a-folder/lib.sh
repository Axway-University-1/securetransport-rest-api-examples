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

# The user to share with: the e-mail address of a user the server knows (02-knowing-yourself/05 lists them)
SHARE_WITH="${ST_SHARE_WITH:-}"

# st_need_collaborator: stop with a hint when no one is named
st_need_collaborator() {
    if [ -z "${SHARE_WITH}" ]; then
        echo "Name the user to share with: export ST_SHARE_WITH=their.address@example.com"
        echo "It must be the e-mail address of a user the server knows: a folder cannot be shared with anyone else."
        echo "(02-knowing-yourself/05.myself_addressBook_GET.sh lists the users and their addresses.)"
        exit 2
    fi
}
