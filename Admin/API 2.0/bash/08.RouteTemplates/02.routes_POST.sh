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
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The names must be unique, as ST rejects a duplicate route template name.
# - This creates 163 route templates. A large number of templates slows the
#   admin UI down noticeably, so consider trimming the list below.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

printf "Loading variables into our context...\n"
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

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

# Loop through TEMPLATE_NAMES array and use each name as is
for TEMPLATE_NAME in "${TEMPLATE_NAMES[@]}"; do
        curl -k -u ${ST_USER}:${ST_PASSWORD} -X POST "https://${ST_SERVER}:${ST_PORT}/api/v2.0/routes" -H "accept: */*" -H "${REFERER_HEADER}" -H "Content-Type: application/json" \
        -d "{\"name\": \"${TEMPLATE_NAME}\", \"description\": \"Random text for ${TEMPLATE_NAME}\", \"type\": \"TEMPLATE\", \"conditionType\":\"MATCH_ALL\"}"
done
