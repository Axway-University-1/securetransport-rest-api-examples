#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the
# cookie jar session.cookie.jar of this use case, st_session and st_enc)..
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"
