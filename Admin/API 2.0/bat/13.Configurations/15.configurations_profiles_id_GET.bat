@echo off
REM ==============================================================================
REM Script Name: 15.configurations_profiles_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a configuration profile, using the
REM `/configurations/profiles/{id}` endpoint.
REM
REM Usage:
REM 15.configurations_profiles_id_GET.bat [PROFILE_ID]
REM
REM   PROFILE_ID  the profile (default: the SecureTransport Server Configuration
REM               profile)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A profile's id is a number, and may be negative.
REM - PowerShell is used to look the id up, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PROFILE_ID=%~1
IF NOT "%PROFILE_ID%"=="" GOTO have_id
SET LOOKUP_FILE=%TEMP%\conf_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/profiles" -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
FOR /F %%P IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -eq \"SecureTransport Server Configuration\" })[0].id"') DO SET PROFILE_ID=%%P
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF "%PROFILE_ID%"=="" (
    echo Give the profile's id: 13.configurations_profiles_GET.bat lists them.
    EXIT /B 1
)
:have_id

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/profiles/%PROFILE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"
echo.
