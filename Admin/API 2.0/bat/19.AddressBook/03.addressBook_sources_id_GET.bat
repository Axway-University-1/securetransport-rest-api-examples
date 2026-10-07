@echo off
REM ==============================================================================
REM Script Name: 03.addressBook_sources_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one address book source, using the
REM `/addressBook/sources/{id}` endpoint: its type, group, whether it is enabled,
REM and its custom properties - for LDAP, the domain and the page size.
REM
REM Usage:
REM 03.addressBook_sources_id_GET.bat [SOURCE]
REM
REM   SOURCE  the source's name (default LDAP). Its id is looked up by name.
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/addressBook/sources

SET SOURCE=%~1
IF "%SOURCE%"=="" SET SOURCE=LDAP
SET SOURCE_FILE=%TEMP%\source_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%SOURCE%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SOURCE_FILE%"
SET SOURCE_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SOURCE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SOURCE_ID=%%I
IF "%SOURCE_ID%"=="" (
    echo There is no address book source named %SOURCE%.
    IF EXIST "%SOURCE_FILE%" DEL "%SOURCE_FILE%"
    EXIT /B 1
)
IF EXIST "%SOURCE_FILE%" DEL "%SOURCE_FILE%"

echo The source %SOURCE%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SOURCE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo Only its custom properties:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SOURCE_ID%?fields=customProperties" -H "accept: application/json" -H "%REFERER_HEADER%"
echo.
