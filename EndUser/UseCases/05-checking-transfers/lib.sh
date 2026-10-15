#!/bin/bash
# ==============================================================================
# Script Name: lib.sh
# Author: Plamen Milenkov
# Created: 2026-10-15
# Location: Sofia
# ==============================================================================
# Description:
# Sourced by every script of this use case. Loads ../session.sh (the settings, the
# cookie jar session.cookie.jar of this use case, st_session and st_enc), the line format that lists of transfers are printed in, and a hint for a 403.
#
# Usage:
# source lib.sh
#
# Risk: none
# ==============================================================================

UC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${UC_DIR}/../session.sh"

# The columns of one transfer in a list: name, direction, protocol, status, start time
ROW='"  \(.filename)  \(.direction)  \(.protocol)  \(.status)  \(.startTime)"'

# st_refused CODE: a 403 here is most often an account that may not use the transfers web service
st_refused() {
    [[ "$1" == 403 ]] && echo "403: the account may not use the transfers web service (transfersWebServiceAllowed in GET /myself; the administrator sets it)."
    return 0
}
