@echo off
REM ==============================================================================
REM Script Name: 12.configurations_logging_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a logging configuration option, using the
REM `/configurations/logging/{name}` endpoint with PUT: it uploads a log4j XML
REM file as a multipart form.
REM
REM Usage:
REM 12.configurations_logging_name_PUT.bat XML_FILE [NAME [PROFILE_ID]]
REM
REM   XML_FILE    the log4j configuration to upload
REM   NAME        the option (default Logging.Admin.config)
REM   PROFILE_ID  its profile (default: the one 09.configurations_logging_GET.bat
REM               lists it with)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Each logging option belongs to a configuration profile; profileId says which, and is required.
REM - Keep the XML 11.configurations_logging_name_GET.bat saved, to put back.
REM - Confirmed directly: on a server where the option was never set, a PUT
REM   answers 400 "Option ... is not eligible for propagation because its
REM   initial configuration is not fetched yet." and nothing changes.
REM - Changes the server's logging: try it on a test server first.
REM - PowerShell is used to look the profile up, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET XML_FILE=%~1
SET NAME=%~2
IF "%NAME%"=="" SET NAME=Logging.Admin.config
SET PROFILE_ID=%~3
IF NOT EXIST "%XML_FILE%" (
    echo Usage: 12.configurations_logging_name_PUT.bat XML_FILE [NAME [PROFILE_ID]]
    EXIT /B 2
)
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
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=

echo Uploading %XML_FILE% as %NAME%, profile %PROFILE_ID%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/logging/%NAME%?profileId=%PROFILE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" -F "file=@%XML_FILE%;type=application/xml"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="200" GOTO done
IF "%HTTP_CODE%"=="204" GOTO done
TYPE "%RESPONSE_FILE%"
echo.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
