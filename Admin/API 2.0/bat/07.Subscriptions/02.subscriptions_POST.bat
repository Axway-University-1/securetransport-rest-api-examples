@echo off
REM ==============================================================================
REM Script Name: 02.subscriptions_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script subscribes an account's folder to an Advanced Routing application,
REM using the `/applications` and `/subscriptions` endpoints. It demonstrates:
REM - Creating the Advanced Routing application the subscription needs
REM - Creating the subscription, with the pull site as its PARTNER-IN transfer
REM   configuration, so that what the site pulls lands in the folder
REM - Reading the id of the new subscription from the Location header
REM - The HTTP code of each call, from curl itself (-w), not from the head of a headers file
REM
REM Usage:
REM 02.subscriptions_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account "john" and its site SSH_PULL must already exist. Run
REM   06.TransferSites/02.sites_POST_ssh.bat first.
REM - If the application already exists, its POST is refused (400 "An application with
REM   this name already exists.", not a 409) and the subscription is created against
REM   the existing one.
REM - A route only runs on what arrives in the folder once a composite route is
REM   linked to the subscription. See
REM   09.CompositeRoutes/05.routes_POST_composite_subscription.bat.
REM - 04.subscriptions_id_DELETE.bat removes the subscription and the application again.
REM - PowerShell is used to build the request bodies, in place of jq.
REM - The status is read with `curl -w "\n%%{http_code}"`. The older script took it from the first line of the headers file, which is the
REM   line of an interim `HTTP/1.1 100 Continue` or of a redirect when there is one, and so printed the wrong code.
REM - Confirmed directly: the application is 201 with no body; one that exists is 400 "An application with this name already exists." (the
REM   script goes on with the one that is there, and exits 1 for any other refusal). The subscription is 201 with the new id at the end of `Location`.
REM - Exit codes: 0 when the subscription was created (201), 1 when the server refuses the application (other than because it exists) or the
REM   subscription. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

IF NOT "%~1"=="" (
    echo Usage: 02.subscriptions_POST.bat
    EXIT /B 2
)

SET ACCOUNT=john
SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=/inbox
SET PULL_SITE=SSH_PULL
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\subscription_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\subscription_headers_%RANDOM%.txt

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM The two creations; the exit code of the script is the one of this subroutine
REM ------------------------------------------------------------------------------
:main
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type = 'AdvancedRouting'; name = $env:APPLICATION; notes = 'Created by 07.Subscriptions' } | ConvertTo-Json -Compress))"
echo Creating the application '%APPLICATION%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/applications" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="201" GOTO subscribe
CALL :show_error
SET MAYBE_EXISTS=
IF "%HTTP_CODE%"=="400" SET MAYBE_EXISTS=yes
IF "%HTTP_CODE%"=="409" SET MAYBE_EXISTS=yes
IF NOT "%MAYBE_EXISTS%"=="yes" EXIT /B 1
findstr /C:"already exists" "%RESPONSE_FILE%" >nul
IF ERRORLEVEL 1 EXIT /B 1
echo The application exists already: the subscription goes on it.

:subscribe
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type = 'AdvancedRouting'; account = $env:ACCOUNT; application = $env:APPLICATION; folder = $env:FOLDER; transferConfigurations = @([ordered]@{ tag = 'PARTNER-IN'; outbound = $false; site = $env:PULL_SITE }) } | ConvertTo-Json -Compress -Depth 5))"
echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/subscriptions" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
    CALL :show_error
    EXIT /B 1
)
CALL :show_location "New subscription ID:"
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
