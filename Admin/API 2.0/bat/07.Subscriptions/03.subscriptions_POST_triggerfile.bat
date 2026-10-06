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
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Run 02.subscriptions_POST.bat first. It creates the application and the
REM   site this subscription uses.
REM - The ${...} values below are Expression Language, filled in by
REM   SecureTransport.
REM - The condition holds a regular expression, and its dot is escaped with two
REM   backslashes, \\., as SecureTransport needs.
REM - Features\trigger-route-after-completed-pull runs this whole flow end to end.
REM - PowerShell is used to build the request body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=/inbox-trigger
SET PULL_SITE=SSH_PULL
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json

REM A new name for every pull, built from the date and time of the pull
SET TRIGGER_FILE_NAME=file_${date('yyyyddMMHHmmss')}.trigger
REM True for a file whose name ends in .trigger
SET TRIGGER_CONDITION=${stenv['target'].matches('.*\\.trigger')?1:0}

powershell -NoProfile -Command "@{ type='AdvancedRouting'; account=$env:ACCOUNT; application=$env:APPLICATION; folder=$env:FOLDER; transferConfigurations=@(@{ tag='PARTNER-IN'; outbound=$false; site=$env:PULL_SITE }); createFilesList=@{ createFilesListEnabled=$true; createFilesListFilename=$env:TRIGGER_FILE_NAME }; postTransmissionActions=@{ submitFilterType='TRIGGER_FILE_CONTENT'; triggerFileOption='fail'; triggerOnConditionEnabled=$true; triggerOnConditionExpression=$env:TRIGGER_CONDITION } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%', with a trigger file...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" -d "@%BODY_FILE%"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
