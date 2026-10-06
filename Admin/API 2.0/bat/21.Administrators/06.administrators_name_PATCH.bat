@echo off
REM ==============================================================================
REM Script Name: 06.administrators_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script locks an administrator, using the `/administrators/{name}`
REM endpoint with PATCH: a JSON Patch document that replaces locked. A locked
REM administrator cannot log in.
REM
REM Usage:
REM 06.administrators_name_PATCH.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - 05.administrators_name_PUT.bat unlocks it again.
REM - Confirmed directly: a success answers 204, with no body.
REM - Never point it at the administrator you log in as.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=%~1
IF "%ADMIN%"=="" SET ADMIN=example_admin
IF /I "%ADMIN%"=="%ST_USER%" (
    echo That is the administrator this script logs in as. Not locking it.
    EXIT /B 2
)

echo Locking %ADMIN%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ADMIN%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/locked\",\"value\":true}]"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
