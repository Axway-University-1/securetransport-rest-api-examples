@echo off
REM ==============================================================================
REM Script Name: 04.administrativeRoles_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads an administrative role, using the
REM `/administrativeRoles/{name}` endpoint, and the administrators that hold it,
REM with /administrators?roleName=.
REM
REM Usage:
REM 04.administrativeRoles_name_GET.bat [ROLE]
REM
REM   ROLE  the role's name (default example_role)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the role carries metadata.links.members, a ready made
REM   search for its administrators, but the server encodes it wrongly for a
REM   name with a space (roleName=Master%2BAdministrator finds nobody). This
REM   script searches by the name itself instead.
REM - PowerShell is used to URL-encode the name and print the members, in place
REM   of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=%~1
IF "%ROLE%"=="" SET ROLE=example_role
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ROLE)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\role_%RANDOM%.json
SET MEMBERS_FILE=%TEMP%\role_members_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the role %ROLE% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.

echo.
echo The administrators that hold it:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators" ^
  --data-urlencode "roleName=%ROLE%" --data-urlencode "fields=loginName" -H "accept: application/json" -H "%REFERER_HEADER%" > "%MEMBERS_FILE%"
powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:MEMBERS_FILE | ConvertFrom-Json).result) { '  ' + $a.loginName }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%MEMBERS_FILE%" DEL "%MEMBERS_FILE%"
