#!/bin/bash
# ==============================================================================
# Script Name: 09.unused_objects_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Part B, the answer: the objects that nothing points to, grouped by type, from the map of step 07 and the log search of step 08. With the default prefix (the demo set) the list is compared with the one that was built on purpose: the script says whether
# they are the same, and ends with exit 1 when they are not. Reads nothing from the server (the files of step 07 and 08), so it can be run as often as you like.
#
# Usage:
# ./09.unused_objects_GET.sh [PREFIX]
#
#   PREFIX  the prefix that steps 07 and 08 were run with (default example_unu_)
#
# Risk: none
#
# Notes:
# - Written for this use case. The rules are in unused.jq (README: "The rules"). An object is unused when nothing points to it, and it is a candidate for deletion, not a verdict: see "What to check before you delete" in the README.
# - A reference counts even when it comes from an unused object. The site example_unu_site_step is named by a step of example_unu_rt_orphan, which nothing runs: the site is "used" in this pass. Delete the orphan route, run the steps again, and the site shows up.
# - AS2 and PeSIT sites are never reported (they can be used only to receive, which the configuration does not show). Certificates are judged when they have an owner and are private or local: those are the ones a site can name.
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./09.unused_objects_GET.sh [PREFIX]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: PREFIX.\n%s\n" "$#" "${USAGE}"; exit 2; fi
if [ "$#" -ge 1 ]; then PREFIX="$1"; else PREFIX="${PREFIX_DEFAULT}"; fi
uc_check_prefix "${PREFIX}" "${USAGE}"
if [ ! -s "${MAP_DIR}/routes.json" ] || [ "$(cat "${MAP_DIR}/prefix" 2>/dev/null)" != "${PREFIX}" ]; then
    echo "There is no map for the prefix ${PREFIX}. Run 07.map_relationships_GET.sh ${PREFIX} (and 08) first."
    exit 1
fi
if [ ! -f "${MAP_DIR}/logsearch.tsv" ]; then
    echo "There is no log search for the prefix ${PREFIX}. Run 08.server_log_search_GET.sh ${PREFIX} first."
    exit 1
fi

uc_print_unused "${MAP_DIR}" || exit 1
if [ "${PREFIX}" = "${PREFIX_DEFAULT}" ]; then
    EXPECTED=$(printf '%s\n' "${UC_EXPECTED[@]}" | sort)
    GOT=$(uc_unused "${MAP_DIR}" | awk -F'\t' '$1 == "U" {print $2 "|" $3}' | sort)
    if [ "${EXPECTED}" = "${GOT}" ]; then
        echo "This is the list that was built on purpose: ${#UC_EXPECTED[@]} objects, no more and no fewer."
    else
        echo "This is NOT the list that was built on purpose."
        echo "  Expected and not found:"; comm -23 <(printf '%s\n' "${EXPECTED}") <(printf '%s\n' "${GOT}") | sed 's/^/    /'
        echo "  Found and not expected:"; comm -13 <(printf '%s\n' "${EXPECTED}") <(printf '%s\n' "${GOT}") | sed 's/^/    /'
        exit 1
    fi
fi
