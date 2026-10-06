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
REM through the members link the role carries.
REM
REM Usage:
REM 04.administrativeRoles_name_GET.bat [ROLE]
REM
REM   ROLE  the role's name (default example_role)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the role's metadata.links.members is
REM   /administrators?roleName=<role>&fields=loginName.
REM - PowerShell is used to URL-encode the name, read the link and print the
REM   members, in place of jq.
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

SET MEMBERS_URL=
FOR /F "delims=" %%U IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).metadata.links.members"') DO SET "MEMBERS_URL=%%U"
IF DEFINED MEMBERS_URL (
    echo.
    echo The administrators that hold it:
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MEMBERS_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%MEMBERS_FILE%"
    powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:MEMBERS_FILE | ConvertFrom-Json).result) { '  ' + $a.loginName }"
)

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%MEMBERS_FILE%" DEL "%MEMBERS_FILE%"
