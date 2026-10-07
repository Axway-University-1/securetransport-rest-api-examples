@echo off
REM ==============================================================================
REM Script Name: 04.sites_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes transfer sites using the `/sites/{id}` endpoint.
REM A site is deleted by its id, not its name, so it demonstrates:
REM - Looking up the id of a site by account and name
REM - Deleting the site by that id
REM
REM Usage:
REM 04.sites_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up the two sites 02.sites_POST_ssh.bat creates for the account
REM   "john": SSH_PULL and SSH_PUSH. Only ever point it at sites you created.
REM - A site that a subscription or a route still uses cannot be deleted. Delete
REM   those first (07.Subscriptions, 09.CompositeRoutes).
REM - PowerShell is used to read the id out of the response, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\sites_%RANDOM%.json

FOR %%N IN (SSH_PULL SSH_PUSH) DO CALL :delete_site %%N

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:delete_site
SET NAME=%1
SET SITE_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites?account=%ACCOUNT%&name=%NAME%&fields=id" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SITE_ID=%%I

IF "%SITE_ID%"=="" (
    echo The account '%ACCOUNT%' has no site '%NAME%'.
    EXIT /B 0
)

echo Deleting the site '%NAME%' (%SITE_ID%)...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE ^
  "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites/%SITE_ID%" ^
  -H "accept: */*" -H "%REFERER_HEADER%"
EXIT /B 0
