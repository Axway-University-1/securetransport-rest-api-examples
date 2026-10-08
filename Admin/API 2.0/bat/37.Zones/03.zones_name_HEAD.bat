@echo off
REM ==============================================================================
REM Script Name: 03.zones_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks that a zone exists using the `/zones/{name}` endpoint.
REM It demonstrates:
REM - A HEAD call, which answers with the status only: 200 it exists, 404 it does not
REM
REM Usage:
REM 03.zones_name_HEAD.bat [NAME]
REM
REM   NAME  the zone (default example_zone, which 02 creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: 200 for `Private` and for a zone of ours, 404 with no body for a zone that does not exist or whose name differs only in
REM   case. A name with a space is URL-encoded by this script and found.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_zone
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The zone %NAME% exists.
) ELSE (
    echo The zone %NAME% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
