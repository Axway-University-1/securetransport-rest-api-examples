@echo off
REM ==============================================================================
REM Script Name: 12.subscriptions_POST_types.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script subscribes an account to one application of each of four other types, using
REM the `/applications` and `/subscriptions` endpoints. 02.subscriptions_POST.bat
REM shows Advanced Routing; the others are:
REM - Basic
REM - HumanSystem (Human to System)
REM - MBFT (File Transfer via File Services)
REM - StandardRouter, which also needs the subscriber's ID
REM
REM Usage:
REM 12.subscriptions_POST_types.bat [ACCOUNT]
REM
REM   ACCOUNT  the account to subscribe (default john)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It creates the applications ExampleBasicApplication, ExampleHumanSystemApplication,
REM   ExampleMBFTApplication and ExampleStandardRouterApplication, and the subscriptions on the folders
REM   /example_Basic, /example_HumanSystem, /example_MBFT and /example_StandardRouter of the account.
REM   13.subscriptions_id_DELETE_types.bat removes them again.
REM - An application that exists already is refused (400 "An application with this name already exists.",
REM   not a 409) and the subscription is created against it.
REM - Confirmed directly on the lab: Basic, HumanSystem, MBFT and StandardRouter subscribe with
REM   only the type, account, application and folder (StandardRouter also needs `subscriberID`, 400
REM   "A valid subscriberID should be specified..." without it). SharedFolder and SiteMailbox need more
REM   from their application first (a `sharedFolder`; an `inboxFolder` and `outboxFolder`), and a
REM   SiteMailbox subscription needs an inbound transfer configuration, 400 "SiteMailbox application type
REM   requires inbound transfer configuration."; they are not shown here.
REM - The folders are not made by the POST: they appear in the account's home folder at its next login.
REM - The type of the subscription is the type of its application: a body that says another type is
REM   accepted and the application's type wins. The folder needs no leading /. A second subscription
REM   on the same application and folder (and, for StandardRouter, the same subscriberID) is 400
REM   "All subscriptions to an application should have a unique anchor.". An application that has
REM   subscriptions cannot be deleted, 400 "has active subscriptions"; deleting the account deletes its
REM   subscriptions.
REM - A HumanSystem subscription takes `rules` (enabled, recipientPattern, fileFilterPattern,
REM   targetFolder); this script sets one.
REM - PowerShell is used to build the request bodies, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET FAILED=0

FOR %%T IN (Basic HumanSystem MBFT StandardRouter) DO CALL :subscribe %%T
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

:subscribe
SET TYPE=%1
SET APPLICATION=Example%TYPE%Application
SET FOLDER=/example_%TYPE%
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\subscription_headers_%RANDOM%.txt

powershell -NoProfile -Command "[ordered]@{ type = $env:TYPE; name = $env:APPLICATION; notes = 'Created by 07.Subscriptions' } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Creating the %TYPE% application '%APPLICATION%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "HTTP %%{http_code}\n" -d "@%BODY_FILE%"

powershell -NoProfile -Command "$b = [ordered]@{ type = $env:TYPE; account = $env:ACCOUNT; application = $env:APPLICATION; folder = $env:FOLDER }; if ($env:TYPE -eq 'StandardRouter') { $b.subscriberID = 'EXAMPLE_SUBSCRIBER' }; if ($env:TYPE -eq 'HumanSystem') { $b.rules = @([ordered]@{ enabled = $true; recipientPattern = '*'; fileFilterPattern = '*.txt'; targetFolder = '/example_targets' }) }; $b | ConvertTo-Json -Compress -Depth 5 | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%'...
curl -s -D "%HEADERS_FILE%" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"
SET HTTP_CODE=
FOR /F "tokens=2" %%C IN ('powershell -NoProfile -Command "Get-Content $env:HEADERS_FILE | Select-Object -First 1"') DO SET HTTP_CODE=%%C
SET LOCATION=
SET LOCATION_WORD=Location:
FOR /F "delims=" %%L IN ('powershell -NoProfile -Command "$l = Get-Content $env:HEADERS_FILE | Where-Object { $_.StartsWith($env:LOCATION_WORD) } | Select-Object -First 1; if ($l) { $l.Trim().Split([char]47)[-1] }"') DO SET LOCATION=%%L
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" (
    echo New subscription ID: %LOCATION%
) ELSE (
    SET FAILED=1
)
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B 0
