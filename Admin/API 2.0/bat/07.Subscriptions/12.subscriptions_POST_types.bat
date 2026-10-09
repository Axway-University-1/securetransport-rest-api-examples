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
REM   ACCOUNT  the account to subscribe (default john, or ST_EXAMPLE_ACCOUNT)
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
REM - The status of each call is read with `curl -w "\n%%{http_code}"`, not from the first line of a headers file: that line is the one of an
REM   interim `100 Continue` or of a redirect when there is one, and gave the wrong code.
REM - PowerShell is used to build the request bodies, in place of jq.
REM - Exit codes: 0 when all four subscriptions were created (201), 1 when the server refuses an application (other than because it exists)
REM   or a subscription (the other types are still tried), 2 when the account is empty or there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
IF NOT "%~2"=="" (
    echo Usage: 12.subscriptions_POST_types.bat [ACCOUNT]
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\subscription_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\subscription_headers_%RANDOM%.txt
SET FAILED=0

FOR %%T IN (Basic HumanSystem MBFT StandardRouter) DO CALL :subscribe %%T

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Creates the application of the type %1 and the subscription on it; sets FAILED when the server refuses one
REM ------------------------------------------------------------------------------
:subscribe
SET TYPE=%1
SET APPLICATION=Example%TYPE%Application
SET FOLDER=/example_%TYPE%

powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type = $env:TYPE; name = $env:APPLICATION; notes = 'Created by 07.Subscriptions' } | ConvertTo-Json -Compress))"
echo Creating the %TYPE% application '%APPLICATION%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" GOTO subscribe_now
CALL :show_error
SET MAYBE_EXISTS=
IF "%HTTP_CODE%"=="400" SET MAYBE_EXISTS=yes
IF "%HTTP_CODE%"=="409" SET MAYBE_EXISTS=yes
IF NOT "%MAYBE_EXISTS%"=="yes" GOTO app_refused
findstr /C:"already exists" "%RESPONSE_FILE%" >nul
IF ERRORLEVEL 1 GOTO app_refused
echo The application exists already: the subscription goes on it.

:subscribe_now
powershell -NoProfile -Command "$b = [ordered]@{ type = $env:TYPE; account = $env:ACCOUNT; application = $env:APPLICATION; folder = $env:FOLDER }; if ($env:TYPE -eq 'StandardRouter') { $b.subscriberID = 'EXAMPLE_SUBSCRIBER' }; if ($env:TYPE -eq 'HumanSystem') { $b.rules = @([ordered]@{ enabled = $true; recipientPattern = '*'; fileFilterPattern = '*.txt'; targetFolder = '/example_targets' }) }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 5))"
echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" (
    CALL :show_location "New subscription ID:"
    EXIT /B 0
)
CALL :show_error
SET FAILED=1
EXIT /B 0

:app_refused
SET FAILED=1
EXIT /B 0

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
