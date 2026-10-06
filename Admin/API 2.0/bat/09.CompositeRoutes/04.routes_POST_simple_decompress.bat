@echo off
REM ==============================================================================
REM Script Name: 04.routes_POST_simple_decompress.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a simple route that unpacks the archives it receives and
REM sends the files inside them to a partner, using the `/routes` endpoint.
REM It demonstrates:
REM - A Decompress step, which overwrites a file of the same name
REM - A SendToPartner step that sends only what the step before it produced
REM   (usePrecedingStepFiles), so the unpacked files go out and the archive does not
REM - Reading the id of the new route from the Location header
REM
REM Usage:
REM 04.routes_POST_simple_decompress.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site SSH_PUSH must already exist. Run
REM   06.TransferSites\02.sites_POST_ssh.bat first.
REM - A simple route does nothing on its own. A composite route runs it through an
REM   ExecuteRoute step. See 05.routes_POST_composite_subscription.bat.
REM - PowerShell is used to build the request body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ROUTE_NAME=SimpleRoute_Decompress
SET PUSH_SITE=SSH_PUSH
SET BODY_FILE=%TEMP%\route_body_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\route_headers_%RANDOM%.txt

powershell -NoProfile -Command "@{ type='SIMPLE'; name=$env:ROUTE_NAME; conditionType='ALWAYS'; condition=$true; steps=@( @{ type='Decompress'; status='ENABLED'; conditionType='ALWAYS'; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; filenameCollisionResolutionType='OVERWRITE'; actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:PUSH_SITE + '#!#CVD#!#'); actionOnStepFailure='FAIL' } ) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the simple route '%ROUTE_NAME%'...
curl -s -D "%HEADERS_FILE%" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"

SET HTTP_CODE=
SET LOCATION=
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%HEADERS_FILE%"') DO SET HTTP_CODE=%%C
FOR /F "tokens=2" %%L IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%L
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"

echo.
echo HTTP %HTTP_CODE%
IF DEFINED LOCATION FOR %%P IN ("%LOCATION%") DO echo New route ID: %%~nxP
