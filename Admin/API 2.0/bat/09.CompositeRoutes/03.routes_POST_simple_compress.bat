@echo off
REM ==============================================================================
REM Script Name: 03.routes_POST_simple_compress.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a simple route that compresses the files it receives into
REM one ZIP archive and sends the archive to a partner, using the `/routes`
REM endpoint. It demonstrates:
REM - A Compress step that builds a single archive
REM - A SendToPartner step that sends only what the step before it produced
REM   (usePrecedingStepFiles), so the archive goes out and the originals do not
REM - Reading the id of the new route from the Location header
REM - The HTTP code, from curl itself (-w), not from the head of a headers file
REM
REM Usage:
REM 03.routes_POST_simple_compress.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site SSH_PUSH must already exist. Run
REM   06.TransferSites/02.sites_POST_ssh.bat first.
REM - A simple route does nothing on its own. A composite route runs it through an
REM   ExecuteRoute step. See 05.routes_POST_composite_subscription.bat.
REM - STORE puts the files in the archive without compressing them. Use another
REM   compressionLevel to make the archive smaller.
REM - 07.routes_id_DELETE.bat removes the route again.
REM - PowerShell is used to build the request body, in place of jq.
REM - Confirmed directly: a creation is 201 with no body and the route's address in `Location`, which ends with its id. Run again it makes a second
REM   route of the same name (201 again): two simple routes may share a name. 07.routes_id_DELETE.bat then refuses that name until one is removed by its id.
REM - Exit codes: 0 when the route was created (201), 1 when the server refuses it. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes

IF NOT "%~1"=="" (
    echo Usage: 03.routes_POST_simple_compress.bat
    EXIT /B 2
)

SET ROUTE_NAME=SimpleRoute_Compress
SET PUSH_SITE=SSH_PUSH
SET ARCHIVE_NAME=compressed_files.zip
SET BODY_FILE=%TEMP%\route_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\route_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\route_headers_%RANDOM%.txt

powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (@{ type='SIMPLE'; name=$env:ROUTE_NAME; conditionType='ALWAYS'; condition=$true; steps=@( @{ type='Compress'; status='ENABLED'; conditionType='ALWAYS'; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; singleArchiveEnabled=$true; singleArchiveName=$env:ARCHIVE_NAME; compressionType='ZIP'; compressionLevel='STORE'; actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:PUSH_SITE + '#!#CVD#!#'); actionOnStepFailure='FAIL' } ) } | ConvertTo-Json -Depth 10 -Compress))"

echo Creating the simple route '%ROUTE_NAME%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
SET RC=0
IF NOT "%HTTP_CODE%"=="201" (
    CALL :show_error
    SET RC=1
) ELSE (
    CALL :show_location
)
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM Prints the id at the end of the Location header
REM ------------------------------------------------------------------------------
:show_location
SET LOCATION=
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%B
IF "%LOCATION%"=="" EXIT /B 0
FOR /F "usebackq delims=" %%I IN (`powershell -NoProfile -Command "($env:LOCATION.Trim() -split '/')[-1]"`) DO echo New route ID: %%I
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
