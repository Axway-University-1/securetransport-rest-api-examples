@echo off
REM ==============================================================================
REM Script Name: 03.routes_DELETE_all.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes the 163 route templates that 02.routes_POST.bat creates, using the `/routes/{id}` endpoint.
REM A route is deleted by its id, not its name, so it demonstrates:
REM - Reading the route templates once and looking each name of the list up in that answer, by its exact name
REM - Deleting each template found by its id, with a count (`[12/163]`) and the HTTP code of each
REM
REM Usage:
REM 03.routes_DELETE_all.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It deletes ONLY the templates whose name is one of the 163 names of the list below (the same list as 02.routes_POST.bat), compared
REM   exactly, and only among routes of type TEMPLATE: a template of your own, even one called RouteFromSomething that is not in the list,
REM   is not touched, and neither is a simple or a composite route. A name that is not there is skipped.
REM - A template that a composite route inherits cannot be deleted: delete those composite routes first
REM   (09.CompositeRoutes/07.routes_id_DELETE.bat). THE FIRST REFUSAL STOPS THE SCRIPT (exit 1), with the server's message and how many were
REM   deleted so far; run it again after fixing the cause and it goes on with what is left.
REM - PowerShell is used to read the ids and show the server's own message, in place of jq.
REM - Confirmed directly: each delete is 204 with no body (the 163 took about a minute on the lab); with two templates of its own on the lab, one
REM   called RouteFromSomethingOfMine and one routefromclient (a name of the list in another case), only the 163 were deleted and those two stayed.
REM - Exit codes: 0 when every template was deleted or was not there, 1 when the server refuses the read or a delete. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes

IF NOT "%~1"=="" (
    echo Usage: 03.routes_DELETE_all.bat
    EXIT /B 2
)

REM The route template names 02.routes_POST.bat creates, and nothing else is ever deleted
SET NAMES=RouteFromEngineer RouteFromGovernment RouteFromManager RouteFromClient RouteFromVendor RouteFromSupplier RouteFromCustomer RouteFromPartner ^
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
    RouteFromSailor RouteFromExplorer RouteFromGuide

SET RESPONSE_FILE=%TEMP%\route_response_%RANDOM%.json
SET EXISTING_FILE=%TEMP%\route_templates_%RANDOM%.txt

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%EXISTING_FILE%" DEL "%EXISTING_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM The work; the exit code of the script is the one of this subroutine
REM ------------------------------------------------------------------------------
:main
echo Reading the route templates...
CALL :read_templates
IF ERRORLEVEL 1 EXIT /B 1

SET TOTAL=0
FOR %%N IN (%NAMES%) DO SET /A TOTAL+=1
SET COUNT=0
SET DELETED=0
SET SKIPPED=0
SET STOPPED=
FOR %%N IN (%NAMES%) DO CALL :delete_template %%N
IF DEFINED STOPPED EXIT /B 1
echo Done: %DELETED% route templates deleted, %SKIPPED% were not there.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Deletes the route template named in %1, when it is in the list the server gave; after the first refusal it does nothing
REM ------------------------------------------------------------------------------
:delete_template
IF DEFINED STOPPED EXIT /B 0
SET TEMPLATE_NAME=%1
SET /A COUNT+=1
SET FOUND=0
SET TEMPLATE_ID=
REM Each line of EXISTING_FILE is the name, a colon and the id (hexadecimal); only a line with exactly this name and such an id counts
FOR /F "tokens=1,2 delims=:" %%A IN ('findstr /R /C:"^%TEMPLATE_NAME%:[0-9a-fA-F][0-9a-fA-F]*$" "%EXISTING_FILE%"') DO (
    SET /A FOUND+=1
    SET TEMPLATE_ID=%%B
)
IF "%FOUND%"=="0" (
    echo [%COUNT%/%TOTAL%] %TEMPLATE_NAME% is not there: skipped
    SET /A SKIPPED+=1
    EXIT /B 0
)
IF NOT "%FOUND%"=="1" (
    echo [%COUNT%/%TOTAL%] %TEMPLATE_NAME%: %FOUND% templates have this name; none deleted. Stopped: %DELETED% deleted so far.
    SET STOPPED=yes
    EXIT /B 0
)
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%TEMPLATE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo [%COUNT%/%TOTAL%] %TEMPLATE_NAME% (%TEMPLATE_ID%) HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET STOPPED=yes
    SET /A LEFT=TOTAL-COUNT
    CALL :stopped_message
    EXIT /B 0
)
SET /A DELETED+=1
EXIT /B 0

:stopped_message
echo Stopped at the first refusal: %DELETED% deleted, %SKIPPED% skipped, %LEFT% not tried.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Writes the route templates that exist into EXISTING_FILE, one line each (see the caller for the form); 1 when the server refuses the read
REM ------------------------------------------------------------------------------
:read_templates
IF EXIST "%EXISTING_FILE%" DEL "%EXISTING_FILE%"
SET OFFSET=0
:read_page
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "type=TEMPLATE" --data-urlencode "fields=id,name" --data-urlencode "limit=200" --data-urlencode "offset=%OFFSET%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the route templates: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
SET PAGE_COUNT=0
FOR /F %%N IN ('powershell -NoProfile -Command "$l = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null }); $l | ForEach-Object { Add-Content -Path $env:EXISTING_FILE -Value ($_.name + [char]58 + $_.id) }; $l.Count"') DO SET PAGE_COUNT=%%N
IF %PAGE_COUNT% LSS 200 (
    IF NOT EXIST "%EXISTING_FILE%" type nul > "%EXISTING_FILE%"
    EXIT /B 0
)
SET /A OFFSET+=200
GOTO read_page

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
