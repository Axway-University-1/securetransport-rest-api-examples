@echo off
REM ==============================================================================
REM Script Name: 03.administrators_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether an administrator exists, using the
REM `/administrators/{name}` endpoint with HEAD: 200 when it does, 404 when it
REM does not.
REM
REM Usage:
REM 03.administrators_name_HEAD.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to URL-encode the login name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET "ADMIN=%~1"
IF "%ADMIN%"=="" SET ADMIN=example_admin
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ADMIN)"') DO SET "ENCODED=%%E"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The administrator %ADMIN% exists.
) ELSE (
    echo The administrator %ADMIN% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
EXIT /B 0
