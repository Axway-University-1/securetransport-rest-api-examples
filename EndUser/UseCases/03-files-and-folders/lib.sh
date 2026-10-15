#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the
# cookie jar session.cookie.jar of this use case, st_session and st_enc), and the names it works with.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# What this use case creates: one folder in the home folder of the account, and the files in it.
# 99.cleanup_DELETE.sh removes exactly these names and nothing else.
FOLDER="example_uc_files"
FILE_NAME="notes.txt"
RENAMED="notes_renamed.txt"
