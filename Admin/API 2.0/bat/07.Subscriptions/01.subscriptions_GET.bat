@echo off
REM ==============================================================================
REM Script Name: 01.subscriptions_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves subscriptions using the `/subscriptions` endpoint.
REM A subscription links an account's folder to an application. It demonstrates:
REM - A GET request for all the subscriptions of one account
REM - A GET request filtered by type, printed as one line per subscription
REM
REM Usage:
REM 01.subscriptions_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This example uses the account "john". 02.subscriptions_POST.bat and
REM   03.subscriptions_POST_triggerfile.bat create subscriptions for it.
REM - PowerShell is used to print the short listing, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\subscriptions_%RANDOM%.json

echo Get all the subscriptions of the account '%ACCOUNT%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions?account=%ACCOUNT%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo Get only its Advanced Routing subscriptions, one line each: id, folder, application...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions?account=%ACCOUNT%&type=AdvancedRouting" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $j.result) { '{0}  {1}  {2}' -f $s.id, $s.folder, $s.application }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
