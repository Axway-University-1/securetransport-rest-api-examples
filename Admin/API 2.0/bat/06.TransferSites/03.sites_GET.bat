@echo off
REM ==============================================================================
REM Script Name: 03.sites_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves transfer sites using the `/sites` endpoint.
REM It demonstrates:
REM - A GET request for all the sites of one account
REM - A GET request filtered by protocol, printed as one line per site
REM
REM Usage:
REM 03.sites_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This example uses the account "john". 02.sites_POST_ssh.bat creates two SSH
REM   sites for it.
REM - PowerShell is used to print the short listing, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\sites_%RANDOM%.json

echo Get all the sites of the account '%ACCOUNT%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites?account=%ACCOUNT%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo Get only its SSH sites, one line each: id, name, host:port, folder...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites?account=%ACCOUNT%&protocol=ssh" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $j.result) { $f = $s.downloadFolder; if (-not $f) { $f = $s.uploadFolder }; '{0}  {1}  {2}:{3}  {4}' -f $s.id, $s.name, $s.host, $s.port, $f }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
