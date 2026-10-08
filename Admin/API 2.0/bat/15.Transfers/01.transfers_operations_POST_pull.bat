@echo off
REM ==============================================================================
REM Script Name: 01.transfers_operations_POST_pull.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script starts a pull from a partner, on demand, using the
REM `/transfers/operations?operation=pull` endpoint. The files the site matches
REM are downloaded into a folder of the account.
REM
REM Usage:
REM 01.transfers_operations_POST_pull.bat [ACCOUNT [SITE [DESTINATION_FOLDER]]]
REM
REM   ACCOUNT             the account that pulls (default john)
REM   SITE                the transfer site of that account to pull with (default SSH_PULL)
REM   DESTINATION_FOLDER  the folder of the account the files land in (default /inbox)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account "john" and its site SSH_PULL must already exist. Run
REM   06.TransferSites/02.sites_POST_ssh.bat first.
REM - With awaitResult false, SecureTransport answers 202 as soon as the pull is
REM   accepted, and the pull runs on in the background. Follow it in File
REM   Tracking, or with 16.TransferLogs/01.logs_transfers_GET.bat.
REM - When the destination folder is subscribed to an application, as
REM   07.Subscriptions/02.subscriptions_POST.bat sets up for /inbox, what arrives
REM   there is routed.
REM - The HTTP code is printed. Anything but 202 is a refusal and the script exits 1 with the server's answer: the pull was not started.
REM - Confirmed directly: an account that does not exist is 404 "Cannot find account with name X or it is not accessible", a site
REM   the account does not have 400 "X site does not exist", a body with nothing in it 400 listing every field it lacks
REM   (accountName, site, destinationDirectory).
REM - PowerShell is used to build the request body, in place of jq.
REM - Exit codes: 0 when the pull was accepted (202), 1 when the server refuses, 2 when an argument is empty or there are too many (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET USAGE=Usage: 01.transfers_operations_POST_pull.bat [ACCOUNT [SITE [DESTINATION_FOLDER]]]

SET "ACCOUNT=%~1"
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET "PULL_SITE=%~2"
IF "%PULL_SITE%"=="" SET PULL_SITE=SSH_PULL
SET "DESTINATION_FOLDER=%~3"
IF "%DESTINATION_FOLDER%"=="" SET DESTINATION_FOLDER=/inbox
IF NOT "%~4"=="" (
    echo %USAGE%
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:ACCOUNT.Trim() -eq '' -or $env:PULL_SITE.Trim() -eq '' -or $env:DESTINATION_FOLDER.Trim() -eq '') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo ACCOUNT, SITE and DESTINATION_FOLDER must not be empty.
    echo %USAGE%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\pull_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\pull_response_%RANDOM%.json

powershell -NoProfile -Command "$b = [ordered]@{ accountName = $env:ACCOUNT; site = $env:PULL_SITE; destinationDirectory = $env:DESTINATION_FOLDER; awaitResult = $false }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Pulling with the site '%PULL_SITE%' into '%DESTINATION_FOLDER%' of '%ACCOUNT%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/transfers/operations?operation=pull" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="202" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
