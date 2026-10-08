@echo off
REM ==============================================================================
REM Script Name: 08.subscriptions_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the six Advanced Routing subscriptions these examples use, using the
REM `/subscriptions` endpoint, one per scenario, each pulling from its own site
REM (see 02.sites_POST_pull.bat) into its own folder (subscription/s1 to s6).
REM
REM Scenario 2.1 (only inbound) and scenarios 2.2, 2.3, 2.5 and 2.6 use no special
REM trigger settings: by default, a subscription attached to a route (via that
REM route's own `subscriptions` field, see 10.routes_POST_composite.bat) runs the
REM route once per file as it arrives. Scenario 2.1 has no route attached at all,
REM so its files just land.
REM
REM Scenario 2.4 is the one exception: its two files (file_1_for_compress.txt and
REM file_2_for_compress.txt) need to be compressed together, in ONE route
REM execution, so it uses the same batching mechanism as
REM Features/trigger-route-after-completed-pull: a generated trigger file listing
REM every file the pull just fetched, submitted as the one thing the route acts on.
REM
REM Usage:
REM 08.subscriptions_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 02.sites_POST_pull.bat and 05.applications_POST.bat first.
REM - Uses PowerShell to build the JSON bodies.
REM - Stops at the first subscription the server refuses, and exits 1.
REM - The ids are saved as BT_ID_SUBSCRIPTION_1 to BT_ID_SUBSCRIPTION_6.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

REM Scenario 2.4's batching: a trigger file listing both pulled files, submitted
REM whole once it arrives (see Features/trigger-route-after-completed-pull for
REM how this was confirmed against a real server)
SET TRIGGER_FILE_NAME_LOCAL=file_${date('yyyyddMMHHmmss')}.trigger
SET TRIGGER_CONDITION_LOCAL=${stenv['target'].matches('.*\\.trigger')?1:0}

CALL :create_subscription 1 0
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_subscription 2 0
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_subscription 3 0
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_subscription 4 1
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_subscription 5 0
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_subscription 6 0
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

:create_subscription
SET SCENARIO_N=%1
SET WITH_TRIGGER=%2
SET SITE_NAME=%BT_PULL_SITE_PREFIX%%SCENARIO_N%
SET SUB_FOLDER=%BT_SUBSCRIPTION_FOLDER%/s%SCENARIO_N%
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json

IF "%WITH_TRIGGER%"=="1" (
    powershell -NoProfile -Command "@{ type='AdvancedRouting'; application=$env:BT_APPLICATION; account=$env:BT_TEST_ACCOUNT; folder=$env:SUB_FOLDER; transferConfigurations=@(@{ tag='PARTNER-IN'; outbound=$false; site=$env:SITE_NAME }); createFilesList=@{ createFilesListEnabled=$true; createFilesListFilename=$env:TRIGGER_FILE_NAME_LOCAL }; postTransmissionActions=@{ submitFilterType='TRIGGER_FILE_CONTENT'; triggerFileOption='fail'; triggerOnConditionEnabled=$true; triggerOnConditionExpression=$env:TRIGGER_CONDITION_LOCAL } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
) ELSE (
    powershell -NoProfile -Command "@{ type='AdvancedRouting'; application=$env:BT_APPLICATION; account=$env:BT_TEST_ACCOUNT; folder=$env:SUB_FOLDER; transferConfigurations=@(@{ tag='PARTNER-IN'; outbound=$false; site=$env:SITE_NAME }) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
)

echo Creating the subscription for scenario %SCENARIO_N%, on %SUB_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" subscriptions "%BODY_FILE%" BT_ID_SUBSCRIPTION_%SCENARIO_N%
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
