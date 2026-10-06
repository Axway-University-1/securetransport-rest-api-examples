@echo off
REM ==============================================================================
REM Script Name: 01.administrativeRoles_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the administrative roles using the `/administrativeRoles`
REM endpoint. A role is the set of Admin UI menus - and with them, API resources -
REM an administrator may use. It demonstrates:
REM - Listing the roles, a page at a time
REM - Filtering: only the limited roles
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.administrativeRoles_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - roleName, isLimited, isBounceAllowed and menus filter too.
REM - Confirmed directly: fields=roleType is refused ("Field roleType does not
REM   exist."), although a role read whole carries roleType.
REM - Each role has a link to its members: the administrators that hold it.
REM - PowerShell is used to print one role per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET RESPONSE_FILE=%TEMP%\roles_%RANDOM%.json

echo The first 5 roles:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=5&offset=0" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The limited roles, one line each: name, the menus they open:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?isLimited=true&fields=roleName,menus" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($x in $r.result) { '  {0}: {1}' -f $x.roleName, ($x.menus -join ', ') }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
