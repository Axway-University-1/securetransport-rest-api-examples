@echo off
REM ==============================================================================
REM Script Name: 03.subscriptions_POST_triggerfile.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a subscription that writes a trigger file after each
REM pull, and starts routing only when that trigger file arrives, using the
REM `/subscriptions` endpoint. It demonstrates:
REM - createFilesList, which writes the names of the pulled files into a trigger
REM   file in the subscription folder
REM - postTransmissionActions with submitFilterType TRIGGER_FILE_CONTENT, so the
REM   route processes the files the trigger file lists, not each file on arrival
REM - A trigger condition in Expression Language, so only a file whose name ends
REM   in .trigger starts the route
REM
REM Usage:
REM 03.subscriptions_POST_triggerfile.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Run 02.subscriptions_POST.bat first. It creates the application and the
REM   site this subscription uses.
REM - The ${...} values below are Expression Language, filled in by
REM   SecureTransport. They are not batch variables.
REM - The condition holds a regular expression, and its dot is escaped with two
REM   backslashes, \\., as SecureTransport needs. See
REM   14.ExpressionLanguage/05.routes_step_condition_matches_backslashDoubling.bat.
REM - Features/trigger-route-after-completed-pull runs this whole flow end to end.
REM - 04.subscriptions_id_DELETE.bat removes the subscription again.
REM - PowerShell is used to build the request body, in place of jq.
REM - Exit codes: 0 when the subscription was created (201), 1 when the server refuses it. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions

IF NOT "%~1"=="" (
    echo Usage: 03.subscriptions_POST_triggerfile.bat
    EXIT /B 2
)

SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=/inbox-trigger
SET PULL_SITE=SSH_PULL
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\subscription_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\subscription_headers_%RANDOM%.txt

REM A new name for every pull, built from the date and time of the pull
SET TRIGGER_FILE_NAME=file_${date('yyyyddMMHHmmss')}.trigger
REM True for a file whose name ends in .trigger
SET TRIGGER_CONDITION=${stenv['target'].matches('.*\\.trigger')?1:0}

powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (@{ type='AdvancedRouting'; account=$env:ACCOUNT; application=$env:APPLICATION; folder=$env:FOLDER; transferConfigurations=@(@{ tag='PARTNER-IN'; outbound=$false; site=$env:PULL_SITE }); createFilesList=@{ createFilesListEnabled=$true; createFilesListFilename=$env:TRIGGER_FILE_NAME }; postTransmissionActions=@{ submitFilterType='TRIGGER_FILE_CONTENT'; triggerFileOption='fail'; triggerOnConditionEnabled=$true; triggerOnConditionExpression=$env:TRIGGER_CONDITION } } | ConvertTo-Json -Depth 10 -Compress))"

echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%', with a trigger file...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
SET RC=0
IF NOT "%HTTP_CODE%"=="201" (
    CALL :show_error
    SET RC=1
) ELSE (
    CALL :show_location "New subscription ID:"
)
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM Prints the id at the end of the Location header in HEADERS_FILE, labelled with %1
REM ------------------------------------------------------------------------------
:show_location
SET LOCATION=
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%B
IF "%LOCATION%"=="" EXIT /B 0
FOR /F "usebackq delims=" %%I IN (`powershell -NoProfile -Command "($env:LOCATION.Trim() -split '/')[-1]"`) DO echo %~1 %%I
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
