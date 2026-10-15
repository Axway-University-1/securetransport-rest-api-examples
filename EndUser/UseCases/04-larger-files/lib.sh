#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the
# cookie jar session.cookie.jar of this use case, st_session and st_enc), the names it works with, and two helpers for a sample file and its MD5.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# What this use case creates: one folder in the home folder, and the files in it.
# 99.cleanup_DELETE.sh removes exactly these names and nothing else.
FOLDER="example_uc_large"
MD5_FILE="example_md5.bin"
CHUNKED_FILE="example_chunked.bin"
MULTIPART_FILE="example_multipart.bin"
BULK_FILES="example_bulk_1.txt example_bulk_2.txt example_bulk_3.txt"

# st_sample FILE BYTES [TAG]: writes a file of that many bytes, the same every time for the same TAG, so that a
# script can tell what the server should say about it
st_sample() { yes "example content, ${3:-sample}" 2>/dev/null | head -c "$2" > "$1"; }
# st_md5 FILE: the MD5 of the file as base64 of its 16 raw bytes, the form the server uses
st_md5() { openssl dgst -md5 -binary "$1" | openssl base64; }
