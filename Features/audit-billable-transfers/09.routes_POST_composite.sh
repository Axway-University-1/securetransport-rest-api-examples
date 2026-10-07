#!/bin/bash
# ==============================================================================
# Script Name: 09.routes_POST_composite.sh
# Author: Plamen Milenkov
# Created: 2026-10-01
# Location: Sofia
# ==============================================================================
# Description:
# Creates the five composite routes that tie it together, using the `/routes`
# endpoint, one per scenario that has an outbound leg (2.2 to 2.6). Each is
# built from the one template, attached to its own subscription, and has one
# ExecuteRoute step that runs its own simple route.
#
# Usage:
# ./09.routes_POST_composite.sh
#
# Risk: write
#
# Notes:
# - Needs the ids saved by 06.routes_POST_template.sh, 07.routes_POST_simple.sh
#   and 08.subscriptions_POST.sh.
# - Requires `jq`, which builds the JSON bodies.
# - The ids are saved as BT_ID_COMPOSITE_2 to BT_ID_COMPOSITE_6.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# Ends this script, without changing anything, on a server that is too old
source "${SCRIPT_DIR}/../lib/st_feature_check.sh" "5.5-20260924"
source "${SCRIPT_DIR}/settings.sh"

TEMPLATE_ID=$(ar_state_get BT_ID_TEMPLATE)
if [ -z "${TEMPLATE_ID}" ]; then
    printf "BT_ID_TEMPLATE is not saved. Run 06.routes_POST_template.sh first.\n"
    exit 1
fi

create_composite_route() {
    local n="$1"
    local name="${BT_COMPOSITE_ROUTE_PREFIX}${n}"
    local sub_id simple_id body

    sub_id=$(ar_state_get "BT_ID_SUBSCRIPTION_${n}")
    simple_id=$(ar_state_get "BT_ID_SIMPLE_${n}")
    if [ -z "${sub_id}" ] || [ -z "${simple_id}" ]; then
        printf "BT_ID_SUBSCRIPTION_%s or BT_ID_SIMPLE_%s is not saved. Run 07.routes_POST_simple.sh and 08.subscriptions_POST.sh first.\n" "${n}" "${n}"
        return 1
    fi

    body=$(jq -n --arg name "${name}" --arg account "${BT_TEST_ACCOUNT}" \
      --arg template "${TEMPLATE_ID}" --arg sub "${sub_id}" --arg simple "${simple_id}" \
      '{type: "COMPOSITE", account: $account, name: $name, conditionType: "MATCH_ALL",
        routeTemplate: $template, subscriptions: [$sub],
        steps: [{type: "ExecuteRoute", status: "ENABLED", autostart: false, executeRoute: $simple}]}')

    printf "Creating the composite route %s...\n" "${name}"
    ar_admin_post "routes" "${body}" "BT_ID_COMPOSITE_${n}"
}

for n in 2 3 4 5 6; do
    create_composite_route "${n}"
done
