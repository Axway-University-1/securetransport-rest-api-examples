@echo off
REM ==============================================================================
REM Script Name: 11.configurations_logging_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a logging configuration option, using the
REM `/configurations/logging/{name}` endpoint: as JSON, its profile and status;
REM as XML, the log4j configuration itself, saved to a file.
REM
REM Usage:
REM 11.configurations_logging_name_GET.bat [NAME [PROFILE_ID]]
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
REM - The XML is written to NAME.xml, in the current folder.
REM - Confirmed directly: the JSON never holds the XML; ask for it with
REM   "accept: application/xml". An option with no XML set answers 204, and the
REM   server then uses its own default configuration.
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
SET OUTPUT=%NAME%.xml

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/logging/%NAME%?profileId=%PROFILE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"
echo.
echo.
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%OUTPUT%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/logging/%NAME%?profileId=%PROFILE_ID%" -H "accept: application/xml" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    FOR %%A IN ("%OUTPUT%") DO echo Its XML: written to %OUTPUT%, %%~zA bytes.
    GOTO :EOF
)
IF "%HTTP_CODE%"=="204" (
    IF EXIST "%OUTPUT%" DEL "%OUTPUT%"
    echo Its XML: none set ^(HTTP 204^): the server uses its default.
    GOTO :EOF
)
echo Its XML: HTTP %HTTP_CODE%
TYPE "%OUTPUT%"
DEL "%OUTPUT%"
EXIT /B 1
