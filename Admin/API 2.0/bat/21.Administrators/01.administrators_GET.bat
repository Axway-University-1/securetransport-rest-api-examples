@echo off
REM ==============================================================================
REM Script Name: 01.administrators_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the administrators using the `/administrators` endpoint.
REM It demonstrates:
REM - Listing them, a page at a time
REM - Filtering: the administrators that hold a role, the locked ones
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.administrators_GET.bat [ROLE]
REM
REM   ROLE  the role to list the administrators of (default Master Administrator)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Many more filters exist: parent, isLimited, localAuthentication,
REM   dualAuthentication, the password and login times, and the API keys' dates
REM   and permissions. See the API reference.
REM - PowerShell is used to print one administrator per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ROLE=%~1
IF "%ROLE%"=="" SET ROLE=Master Administrator
SET RESPONSE_FILE=%TEMP%\admins_%RANDOM%.json

echo The first 5 administrators, login name and role:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=5&offset=0&fields=loginName,roleName" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The ones that hold %ROLE%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "roleName=%ROLE%" ^
  --data-urlencode "fields=loginName,parent,locked" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { $p = $a.parent; if (-not $p) { $p = '-' }; $l = ''; if ($a.locked) { $l = '  LOCKED' }; '  {0}  created by {1}{2}' -f $a.loginName, $p, $l }"

echo.
echo The locked ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?locked=true&fields=loginName" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  ' + $a.loginName }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
