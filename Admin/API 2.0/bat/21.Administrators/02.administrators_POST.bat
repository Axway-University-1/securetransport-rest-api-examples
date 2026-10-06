@echo off
REM ==============================================================================
REM Script Name: 02.administrators_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates an administrator using the `/administrators` endpoint: a
REM login name, a role, and a password.
REM
REM Usage:
REM 02.administrators_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The administrator is example_admin, with the role example_role: run
REM   20.AdministrativeRoles/02.administrativeRoles_POST.bat first.
REM   ADMIN_PASSWORD is read from the environment, so set it first:
REM     SET ADMIN_PASSWORD=the password
REM - Confirmed directly: parent - the administrator it is created under - is
REM   needed, though the API reference does not mark it required. Without it:
REM   400 "Please specify parent administrator". Here it is ST_USER.
REM - 07.administrators_name_DELETE.bat removes it again.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin
SET ROLE=example_role
IF "%ADMIN_PASSWORD%"=="" SET ADMIN_PASSWORD=change_me
SET BODY_FILE=%TEMP%\admin_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\admin_response_%RANDOM%.json

powershell -NoProfile -Command "@{ loginName=$env:ADMIN; roleName=$env:ROLE; parent=$env:ST_USER; localAuthentication=$true; passwordCredentials=@{ password=$env:ADMIN_PASSWORD } } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Creating the administrator %ADMIN%, role %ROLE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
TYPE "%RESPONSE_FILE%"
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="201" EXIT /B 1
