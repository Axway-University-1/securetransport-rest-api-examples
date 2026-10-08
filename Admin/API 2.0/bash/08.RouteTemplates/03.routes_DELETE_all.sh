#!/bin/bash
# ==============================================================================
# Script Name: 03.routes_DELETE_all.sh
# Author: Plamen Milenkov
# Created: 2026-10-08
# Location: Sofia
# ==============================================================================
# Description:
# This script deletes the 163 route templates that 02.routes_POST.sh creates, using the `/routes/{id}` endpoint.
# A route is deleted by its id, not its name, so it demonstrates:
# - Reading the route templates once and looking each name of the list up in that answer, by its exact name
# - Deleting each template found by its id, with a count (`[12/163]`) and the HTTP code of each
#
# Usage:
# ./03.routes_DELETE_all.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - It deletes ONLY the templates whose name is one of the 163 names of the list below (the same list as 02.routes_POST.sh), compared
#   exactly, and only among routes of type TEMPLATE: a template of your own, even one called RouteFromSomething that is not in the list,
#   is not touched, and neither is a simple or a composite route. A name that is not there is skipped.
# - A template that a composite route inherits cannot be deleted: delete those composite routes first
#   (09.CompositeRoutes/07.routes_id_DELETE.sh). THE FIRST REFUSAL STOPS THE SCRIPT (exit 1), with the server's message and how many were
#   deleted so far; run it again after fixing the cause and it goes on with what is left.
# - Requires `jq`, which reads the ids and shows the server's own message.
# - Confirmed directly: each delete is 204 with no body (the 163 took about a minute on the lab); with two templates of its own on the lab, one
#   called RouteFromSomethingOfMine and one routefromclient (a name of the list in another case), only the 163 were deleted and those two stayed.
# - Exit codes: 0 when every template was deleted or was not there, 1 when the server refuses the read or a delete. It takes no argument.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./03.routes_DELETE_all.sh\n"
    exit 2
fi

# The route template names 02.routes_POST.sh creates, and nothing else is ever deleted
declare -a TEMPLATE_NAMES=(
        "RouteFromEngineer" "RouteFromGovernment" "RouteFromManager" "RouteFromClient" "RouteFromVendor" "RouteFromSupplier"
        "RouteFromCustomer" "RouteFromPartner" "RouteFromDistributor" "RouteFromRetailer" "RouteFromWholesaler" "RouteFromAgent"
        "RouteFromBroker" "RouteFromConsultant" "RouteFromContractor" "RouteFromInvestor" "RouteFromStakeholder" "RouteFromAuditor"
        "RouteFromInspector" "RouteFromAdvisor" "RouteFromDirector" "RouteFromExecutive" "RouteFromAdministrator" "RouteFromCoordinator"
        "RouteFromSupervisor" "RouteFromTechnician" "RouteFromSpecialist" "RouteFromAnalyst" "RouteFromStrategist" "RouteFromPlanner"
        "RouteFromArchitect" "RouteFromDesigner" "RouteFromDeveloper" "RouteFromProgrammer" "RouteFromTester" "RouteFromTrainer"
        "RouteFromInstructor" "RouteFromProfessor" "RouteFromScientist" "RouteFromResearcher" "RouteFromDoctor" "RouteFromNurse"
        "RouteFromPharmacist" "RouteFromTherapist" "RouteFromLawyer" "RouteFromJudge" "RouteFromOfficer" "RouteFromDetective"
        "RouteFromSoldier" "RouteFromPilot" "RouteFromDriver" "RouteFromCourier" "RouteFromMessenger" "RouteFromOperator"
        "RouteFromMachinist" "RouteFromAssembler" "RouteFromFabricator" "RouteFromWelder" "RouteFromElectrician" "RouteFromPlumber"
        "RouteFromCarpenter" "RouteFromPainter" "RouteFromMechanic" "RouteFromTechnologist" "RouteFromBiologist" "RouteFromChemist"
        "RouteFromPhysicist" "RouteFromEconomist" "RouteFromAccountant" "RouteFromBookkeeper" "RouteFromTreasurer" "RouteFromBanker"
        "RouteFromFinancier" "RouteFromTrader" "RouteFromMerchant" "RouteFromMarketer" "RouteFromAdvertiser" "RouteFromPromoter"
        "RouteFromPublisher" "RouteFromEditor" "RouteFromWriter" "RouteFromJournalist" "RouteFromReporter" "RouteFromPhotographer"
        "RouteFromArtist" "RouteFromMusician" "RouteFromActor" "RouteFromProducer" "RouteFromCameraman" "RouteFromAnimator"
        "RouteFromIllustrator" "RouteFromStylist" "RouteFromTailor" "RouteFromChef" "RouteFromBaker" "RouteFromButcher"
        "RouteFromFarmer" "RouteFromGardener" "RouteFromFisherman" "RouteFromHunter" "RouteFromMiner" "RouteFromLogger"
        "RouteFromRancher" "RouteFromBreeder" "RouteFromHandler" "RouteFromZookeeper" "RouteFromVeterinarian" "RouteFromCaretaker"
        "RouteFromCleaner" "RouteFromJanitor" "RouteFromCustodian" "RouteFromSecurity" "RouteFromGuard" "RouteFromPatrol"
        "RouteFromWatchman" "RouteFromFirefighter" "RouteFromParamedic" "RouteFromRescuer" "RouteFromVolunteer" "RouteFromActivist"
        "RouteFromOrganizer" "RouteFromLeader" "RouteFromMember" "RouteFromParticipant" "RouteFromSupporter" "RouteFromFollower"
        "RouteFromSubscriber" "RouteFromUser" "RouteFromViewer" "RouteFromListener" "RouteFromReader" "RouteFromLearner"
        "RouteFromStudent" "RouteFromApprentice" "RouteFromIntern" "RouteFromTrainee" "RouteFromCandidate" "RouteFromApplicant"
        "RouteFromNominee" "RouteFromWinner" "RouteFromChampion" "RouteFromCompetitor" "RouteFromPlayer" "RouteFromAthlete"
        "RouteFromCoach" "RouteFromReferee" "RouteFromUmpire" "RouteFromOfficial" "RouteFromSponsor" "RouteFromDonor"
        "RouteFromBenefactor" "RouteFromPhilanthropist" "RouteFromAdvocate" "RouteFromAmbassador" "RouteFromEnvoy" "RouteFromDiplomat"
        "RouteFromConsul" "RouteFromEmissary" "RouteFromTransporter" "RouteFromCaptain" "RouteFromSailor" "RouteFromExplorer"
        "RouteFromGuide"
)

# The answer to a refused call: the server's own messages, or the text as it is
show_error() { printf '%s' "$1" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "$1"; }

# The route templates that exist, one line each: the name, a tab, the id (the filter is not exact, so the names are compared below)
printf "Reading the route templates...\n"
EXISTING=""
OFFSET=0
while :; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
      --data-urlencode "type=TEMPLATE" --data-urlencode "fields=id,name" --data-urlencode "limit=200" --data-urlencode "offset=${OFFSET}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the route templates: HTTP %s\n" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        exit 1
    fi
    PAGE=$(printf '%s' "${RESPONSE}" | jq -r '(.result // [])[] | select(.type == null or .type == "TEMPLATE") | "\(.name)\t\(.id)"')
    EXISTING="${EXISTING}${PAGE}"$'\n'
    if [ "$(printf '%s' "${RESPONSE}" | jq '(.result // []) | length')" -lt 200 ]; then break; fi
    OFFSET=$((OFFSET + 200))
done

TOTAL=${#TEMPLATE_NAMES[@]}
COUNT=0
DELETED=0
SKIPPED=0
for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"; do
    COUNT=$((COUNT + 1))
    IDS=$(printf '%s' "${EXISTING}" | awk -F'\t' -v name="${TEMPLATE_NAME}" '$1 == name {print $2}')
    FOUND=$(printf '%s' "${IDS}" | grep -c .)
    if [ "${FOUND}" -eq 0 ]; then
        printf "[%d/%d] %s is not there: skipped\n" "${COUNT}" "${TOTAL}" "${TEMPLATE_NAME}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    if [ "${FOUND}" -gt 1 ]; then
        printf "[%d/%d] %s: %s templates have this name; none deleted. Stopped: %d deleted so far.\n" "${COUNT}" "${TOTAL}" "${TEMPLATE_NAME}" "${FOUND}" "${DELETED}"
        exit 1
    fi
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X DELETE "${MAIN_URL}/$(jq -rn --arg n "${IDS}" '$n|@uri')" \
      -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "[%d/%d] %s (%s) HTTP %s\n" "${COUNT}" "${TOTAL}" "${TEMPLATE_NAME}" "${IDS}" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        show_error "${RESPONSE}"
        printf "Stopped at the first refusal: %d deleted, %d skipped, %d not tried.\n" "${DELETED}" "${SKIPPED}" "$((TOTAL - COUNT))"
        exit 1
    fi
    DELETED=$((DELETED + 1))
done
printf "Done: %d route templates deleted, %d were not there.\n" "${DELETED}" "${SKIPPED}"
