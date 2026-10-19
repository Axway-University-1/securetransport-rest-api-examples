#!/bin/bash
# ==============================================================================
# Script Name: 02.routes_POST.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script creates route templates using the `/routes` endpoint.
# It demonstrates creating many objects in a loop, using a list of names that
# follow the structure RouteFromX.
#
# Usage:
# ./02.routes_POST.sh
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.local.sh` is filled in (copy set_variables.local.example.sh).
# - The names must be unique, as ST rejects a duplicate route template name.
# - This creates 163 route templates. A large number of templates slows the
#   admin UI down noticeably, so consider trimming the list below.
# - 03.routes_DELETE_all.sh removes exactly these 163 again, by name (and only templates, never a route that is not one).
# - One call to read the templates that exist already comes first, and a name that is there is skipped, so a run that was
#   stopped halfway can be run again and goes on from where it stopped. Then one POST per name, with a count (`[12/163]`) and the
#   HTTP code of each. THE FIRST REFUSAL STOPS THE SCRIPT (exit 1), with the server's message: there is no point sending 160
#   more after a 403 or a 500.
# - Requires `jq`, which builds each body and reads the names that exist.
# - Confirmed directly: each template is 201 with no body (the 163 took about a minute on the lab); `GET /routes?type=TEMPLATE` takes `limit=200` and
#   pages with `offset`; run twice, the second run reads the 163 and creates none.
# - Exit codes: 0 when every template was created or was there already, 1 when the server refuses the read or a creation. It takes no argument.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${ST_ADMIN_LOCAL_VARIABLES:-${SCRIPT_DIR}/../set_variables.local.sh}" ||
    { echo "Copy set_variables.local.example.sh to set_variables.local.sh and fill it in."; exit 1; }

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes"

if [ "$#" -ne 0 ]; then
    printf "Usage: ./02.routes_POST.sh\n"
    exit 2
fi

# Generate a list of route template names following the structure RouteFromX
# The names must be unique, as ST rejects a duplicate route template name.
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

# The route templates that exist already, one name per line (the filter ignores case and takes a *, so the exact name is compared below)
printf "Reading the route templates that exist already...\n"
EXISTING=""
OFFSET=0
while :; do
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${MAIN_URL}" \
      --data-urlencode "type=TEMPLATE" --data-urlencode "fields=name" --data-urlencode "limit=200" --data-urlencode "offset=${OFFSET}" \
      -H "accept: application/json" -H "${REFERER_HEADER}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    if [ "${HTTP_CODE}" != "200" ]; then
        printf "Could not read the route templates: HTTP %s\n" "${HTTP_CODE}"
        show_error "${RESPONSE}"
        exit 1
    fi
    PAGE=$(printf '%s' "${RESPONSE}" | jq -r '(.result // [])[] | .name')
    EXISTING="${EXISTING}${PAGE}"$'\n'
    if [ "$(printf '%s' "${RESPONSE}" | jq '(.result // []) | length')" -lt 200 ]; then break; fi
    OFFSET=$((OFFSET + 200))
done

# Loop through TEMPLATE_NAMES array and use each name as is
TOTAL=${#TEMPLATE_NAMES[@]}
COUNT=0
CREATED=0
SKIPPED=0
for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"; do
    COUNT=$((COUNT + 1))
    if printf '%s' "${EXISTING}" | grep -qxF -- "${TEMPLATE_NAME}"; then
        printf "[%d/%d] %s exists already: skipped\n" "${COUNT}" "${TOTAL}" "${TEMPLATE_NAME}"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    BODY=$(jq -cn --arg name "${TEMPLATE_NAME}" \
      '{name: $name, description: ("Random text for " + $name), type: "TEMPLATE", conditionType: "MATCH_ALL"}')
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X POST "${MAIN_URL}" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
      -d "${BODY}" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "[%d/%d] %s HTTP %s\n" "${COUNT}" "${TOTAL}" "${TEMPLATE_NAME}" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "201" ]; then
        show_error "${RESPONSE}"
        printf "Stopped at the first refusal: %d created, %d skipped, %d not tried.\n" "${CREATED}" "${SKIPPED}" "$((TOTAL - COUNT))"
        exit 1
    fi
    CREATED=$((CREATED + 1))
done
printf "Done: %d route templates created, %d already there.\n" "${CREATED}" "${SKIPPED}"
