#!/bin/bash
# ==============================================================================
# Script Name: 04.routes_POST.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Step 4: the routes. Two route templates (example_unu_tpl_used and example_unu_tpl_unused), four simple routes and two composite routes.
#   example_unu_rt_on      a Compress step. Run by an ENABLED step of the composite route example_unu_comp_used.
#   example_unu_rt_old     a Compress step. Run by a step of the same composite route that is ENABLED now (05 runs a transfer through it) and that step 06 disables.
#   example_unu_rt_never   a Compress step. Run only by a step that is DISABLED from the start: it never ran.
#   example_unu_rt_orphan  a SendToPartner step to example_unu_site_step. No step of any route runs it. (It is what makes the site "used by a route step".)
# example_unu_comp_used is made from the template example_unu_tpl_used for the account a1, started by the subscription /example_unu_in; its steps run rt_on, rt_old (enabled) and rt_never (disabled).
# example_unu_comp_unused is made from the same template, has no step (a composite route needs none) and no subscription starts it.
#
# Usage:
# ./04.routes_POST.sh
#
# Risk: write
#
# Notes:
# - Copied from Admin/API 2.0/bash/08.RouteTemplates/02.routes_POST.sh (the template), 09.CompositeRoutes/03.routes_POST_simple_compress.sh (the simple routes) and 09.CompositeRoutes/05.routes_POST_composite_subscription.sh (the
#   composite route); the steps are the ones of Features/audit-billable-transfers.
# - A composite route runs a simple route through an ExecuteRoute step. The enabled or disabled of a route is the status of that STEP (ENABLED or DISABLED), not a field of the simple route. The simple routes have no account and no template.
# - A simple route can be run by one ExecuteRoute step only: a second step that names it is refused (400 "Route step's execute route cannot be referenced more that once as an execute route.").
# - Needs steps 01 to 03. An object that exists is not made again (exit 1, and it says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./04.routes_POST.sh"
if [ "$#" -gt 0 ]; then printf "%s parameters were given, and none is taken.\n%s\n" "$#" "${USAGE}"; exit 2; fi
st_session

uc_get subscriptions "account=${A1}" "fields=id,folder"
SUB_ID=$(printf '%s' "${LIST_BODY}" | jq -r --arg f "${SUB_FOLDER}" '[(.result // [])[] | select(.folder == $f)][0].id // empty' 2>/dev/null)
[ -n "${SUB_ID}" ] || { echo "The subscription ${SUB_FOLDER} of ${A1} is not on the server. Run 03.subscriptions_POST.sh first."; exit 1; }
[ -n "$(uc_id_of sites "${SITE_STEP}")" ] || { echo "The site ${SITE_STEP} is not on the server. Run 02.partnerships_POST.sh first."; exit 1; }
for NAME in "${TPL_USED}" "${TPL_UNUSED}" "${RT_ON}" "${RT_OLD}" "${RT_NEVER}" "${RT_ORPHAN}" "${COMP_USED}" "${COMP_UNUSED}"; do
    [ -z "$(uc_id_of routes "${NAME}")" ] || { echo "The route ${NAME} exists already. Nothing more was created. Remove it with 99.cleanup_DELETE.sh."; exit 1; }
done

for NAME in "${TPL_USED}" "${TPL_UNUSED}"; do
    echo "Creating the route template ${NAME}..."
    uc_post routes "$(jq -cn --arg name "${NAME}" '{name: $name, description: ("Package template for " + $name), type: "TEMPLATE", conditionType: "MATCH_ALL"}')" || exit 1
done
compress_route() {   # NAME
    jq -cn --arg name "$1" --arg archive "$1.zip" \
      '{name: $name, type: "SIMPLE", conditionType: "ALWAYS",
        steps: [{type: "Compress", status: "ENABLED", conditionType: "ALWAYS", usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
                 singleArchiveEnabled: true, compressionType: "ZIP", compressionLevel: "STORE", singleArchiveName: $archive, actionOnStepFailure: "FAIL"}]}'
}
for NAME in "${RT_ON}" "${RT_OLD}" "${RT_NEVER}"; do
    echo "Creating the simple route ${NAME} (a Compress step)..."
    uc_post routes "$(compress_route "${NAME}")" || exit 1
done
echo "Creating the simple route ${RT_ORPHAN} (a SendToPartner step to ${SITE_STEP})..."
uc_post routes "$(jq -cn --arg name "${RT_ORPHAN}" --arg site "${SITE_STEP}" \
  '{name: $name, type: "SIMPLE", conditionType: "ALWAYS",
    steps: [{type: "SendToPartner", status: "ENABLED", conditionType: "ALWAYS", autostart: false, usePrecedingStepFiles: false, fileFilterExpressionType: "GLOB", fileFilterExpression: "*",
             transferSiteExpressionType: "LIST", transferSiteExpression: ($site + "#!#CVD#!#"), actionOnStepFailure: "FAIL"}]}')" || exit 1

TPL_ID=$(uc_id_of routes "${TPL_USED}")
ON_ID=$(uc_id_of routes "${RT_ON}"); OLD_ID=$(uc_id_of routes "${RT_OLD}"); NEVER_ID=$(uc_id_of routes "${RT_NEVER}")
step() { jq -cn --arg route "$1" --arg status "$2" '{type: "ExecuteRoute", status: $status, autostart: false, executeRoute: $route}'; }
echo "Creating the composite route ${COMP_USED} (steps: ${RT_ON} enabled, ${RT_OLD} enabled, ${RT_NEVER} disabled; started by ${SUB_FOLDER})..."
uc_post routes "$(jq -cn --arg name "${COMP_USED}" --arg account "${A1}" --arg tpl "${TPL_ID}" --arg sub "${SUB_ID}" \
  --argjson s1 "$(step "${ON_ID}" ENABLED)" --argjson s2 "$(step "${OLD_ID}" ENABLED)" --argjson s3 "$(step "${NEVER_ID}" DISABLED)" \
  '{name: $name, type: "COMPOSITE", account: $account, conditionType: "MATCH_ALL", routeTemplate: $tpl, subscriptions: [$sub], steps: [$s1, $s2, $s3]}')" || exit 1
echo "Creating the composite route ${COMP_UNUSED} (no step, no subscription)..."
uc_post routes "$(jq -cn --arg name "${COMP_UNUSED}" --arg account "${A1}" --arg tpl "${TPL_ID}" \
  '{name: $name, type: "COMPOSITE", account: $account, conditionType: "MATCH_ALL", routeTemplate: $tpl}')" || exit 1
