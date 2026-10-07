@echo off
REM ==============================================================================
REM Script Name: 01.sites_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a transfer site using the `/sites` endpoint.
REM
REM Usage:
REM 01.sites_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site is attached to an account, which must already exist. This example
REM   uses the account "john".
REM - The host below points at ST_SERVER, which is only an example. A transfer
REM   site normally points at a partner's server.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

echo Creating a transfer site...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\":\"HTTP\",\"type\":\"http\",\"protocol\":\"http\",\"account\":\"john\",\"host\":\"%ST_SERVER%\",\"port\":\"443\",\"downloadPattern\":\"*\",\"uploadFolder\":\"/\",\"userName\":\"john\"}"
