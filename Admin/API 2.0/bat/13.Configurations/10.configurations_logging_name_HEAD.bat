@echo off
REM ==============================================================================
REM Script Name: 10.configurations_logging_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a logging configuration option exists, using the
REM `/configurations/logging/{name}` endpoint with HEAD: 200 when it does, 404
REM when it does not.
REM
REM Usage:
REM 10.configurations_logging_name_HEAD.bat [NAME [PROFILE_ID]]
REM
REM   NAME        the option (default Logging.Admin.config)
REM   PROFILE_ID  its profile (default: the one 09.configurations_logging_GET.bat
REM               lists it with)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Each logging option belongs to a configuration profile; profileId says which, and is required.
REM - PowerShell is used to look the profile up, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF "%NAME%"=="" SET NAME=Logging.Admin.config
SET PROFILE_ID=%~2
IF NOT "%PROFILE_ID%"=="" GOTO have_profile
SET LOOKUP_FILE=%TEMP%\conf_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/logging" -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
FOR /F %%P IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -eq $env:NAME })[0].profileId"') DO SET PROFILE_ID=%%P
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF "%PROFILE_ID%"=="" (
    echo There is no logging option %NAME%.
    EXIT /B 1
)
:have_profile

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/logging/%NAME%?profileId=%PROFILE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The logging option %NAME% in profile %PROFILE_ID% exists.
) ELSE (
    echo The logging option %NAME% in profile %PROFILE_ID% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
