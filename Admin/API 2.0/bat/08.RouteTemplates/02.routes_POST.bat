@echo off
REM ==============================================================================
REM Script Name: 02.routes_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates route templates using the `/routes` endpoint.
REM It demonstrates creating many objects in a loop, using a list of names that
REM follow the structure RouteFromX.
REM
REM Usage:
REM 02.routes_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The names must be unique, as ST rejects a duplicate route template name.
REM - This creates 163 route templates. A large number of templates slows the
REM   admin UI down noticeably, so consider trimming the list below.
REM - Each route is created by a CALL to the create_route subroutine. Each CALL
REM   is its own statement, so no delayed expansion is needed.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes

FOR %%N IN ( ^
    RouteFromEngineer RouteFromGovernment RouteFromManager RouteFromClient RouteFromVendor RouteFromSupplier RouteFromCustomer RouteFromPartner ^
    RouteFromDistributor RouteFromRetailer RouteFromWholesaler RouteFromAgent RouteFromBroker RouteFromConsultant RouteFromContractor RouteFromInvestor ^
    RouteFromStakeholder RouteFromAuditor RouteFromInspector RouteFromAdvisor RouteFromDirector RouteFromExecutive RouteFromAdministrator RouteFromCoordinator ^
    RouteFromSupervisor RouteFromTechnician RouteFromSpecialist RouteFromAnalyst RouteFromStrategist RouteFromPlanner RouteFromArchitect RouteFromDesigner ^
    RouteFromDeveloper RouteFromProgrammer RouteFromTester RouteFromTrainer RouteFromInstructor RouteFromProfessor RouteFromScientist RouteFromResearcher ^
    RouteFromDoctor RouteFromNurse RouteFromPharmacist RouteFromTherapist RouteFromLawyer RouteFromJudge RouteFromOfficer RouteFromDetective ^
    RouteFromSoldier RouteFromPilot RouteFromDriver RouteFromCourier RouteFromMessenger RouteFromOperator RouteFromMachinist RouteFromAssembler ^
    RouteFromFabricator RouteFromWelder RouteFromElectrician RouteFromPlumber RouteFromCarpenter RouteFromPainter RouteFromMechanic RouteFromTechnologist ^
    RouteFromBiologist RouteFromChemist RouteFromPhysicist RouteFromEconomist RouteFromAccountant RouteFromBookkeeper RouteFromTreasurer RouteFromBanker ^
    RouteFromFinancier RouteFromTrader RouteFromMerchant RouteFromMarketer RouteFromAdvertiser RouteFromPromoter RouteFromPublisher RouteFromEditor ^
    RouteFromWriter RouteFromJournalist RouteFromReporter RouteFromPhotographer RouteFromArtist RouteFromMusician RouteFromActor RouteFromProducer ^
    RouteFromCameraman RouteFromAnimator RouteFromIllustrator RouteFromStylist RouteFromTailor RouteFromChef RouteFromBaker RouteFromButcher ^
    RouteFromFarmer RouteFromGardener RouteFromFisherman RouteFromHunter RouteFromMiner RouteFromLogger RouteFromRancher RouteFromBreeder ^
    RouteFromHandler RouteFromZookeeper RouteFromVeterinarian RouteFromCaretaker RouteFromCleaner RouteFromJanitor RouteFromCustodian RouteFromSecurity ^
    RouteFromGuard RouteFromPatrol RouteFromWatchman RouteFromFirefighter RouteFromParamedic RouteFromRescuer RouteFromVolunteer RouteFromActivist ^
    RouteFromOrganizer RouteFromLeader RouteFromMember RouteFromParticipant RouteFromSupporter RouteFromFollower RouteFromSubscriber RouteFromUser ^
    RouteFromViewer RouteFromListener RouteFromReader RouteFromLearner RouteFromStudent RouteFromApprentice RouteFromIntern RouteFromTrainee ^
    RouteFromCandidate RouteFromApplicant RouteFromNominee RouteFromWinner RouteFromChampion RouteFromCompetitor RouteFromPlayer RouteFromAthlete ^
    RouteFromCoach RouteFromReferee RouteFromUmpire RouteFromOfficial RouteFromSponsor RouteFromDonor RouteFromBenefactor RouteFromPhilanthropist ^
    RouteFromAdvocate RouteFromAmbassador RouteFromEnvoy RouteFromDiplomat RouteFromConsul RouteFromEmissary RouteFromTransporter RouteFromCaptain ^
    RouteFromSailor RouteFromExplorer RouteFromGuide ^
) DO CALL :create_route %%N

EXIT /B 0

REM ------------------------------------------------------------------------------
REM Creates a route template named in %1
REM ------------------------------------------------------------------------------
:create_route
SET TEMPLATE_NAME=%1

curl -s -o nul -w "%%{http_code}  %TEMPLATE_NAME%\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" ^
-H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\": \"%TEMPLATE_NAME%\", \"description\": \"Random text for %TEMPLATE_NAME%\", \"type\": \"TEMPLATE\", \"conditionType\":\"MATCH_ALL\"}"
EXIT /B
