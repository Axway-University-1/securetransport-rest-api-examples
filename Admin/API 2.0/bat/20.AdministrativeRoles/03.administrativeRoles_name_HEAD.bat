@echo off
REM ==============================================================================
REM Script Name: 03.administrativeRoles_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether an administrative role exists, using the
REM `/administrativeRoles/{name}` endpoint with HEAD: 200 when it does, 404 when
REM it does not.
REM
REM Usage:
REM 03.administrativeRoles_name_HEAD.bat [ROLE]
REM
REM   ROLE  the role's name (default example_role)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A role name with spaces is URL-encoded in the path, as here.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=%~1
IF "%ROLE%"=="" SET ROLE=example_role
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ROLE)"') DO SET "ENCODED=%%E"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The role %ROLE% exists.
) ELSE (
    echo The role %ROLE% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
