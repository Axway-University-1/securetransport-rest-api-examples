@echo off
REM ==============================================================================
REM Script Name: 07.zones_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a zone using the `/zones/{name}` endpoint.
REM It demonstrates:
REM - Deleting a zone by name, and printing the server's reason when it refuses
REM
REM Usage:
REM 07.zones_name_DELETE.bat NAME
REM
REM   NAME  the zone to delete (required: never run it on `Private`, the back end's own zone)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a success answers 204; deleting a zone that is not there is 404 "Zone with name X not found." (a second delete too). A zone
REM   that a business unit still names as its `dmz` is refused with **500** "Database error deleting DMZ zone: X"; take the zone off the unit or delete the
REM   unit first (see 04.zones_name_GET.bat for the units that name it). Deleting the default zone works.
REM - PowerShell is used to URL-encode the name and print the server's reason, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 07.zones_name_DELETE.bat NAME
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\zone_delete_%RANDOM%.json

echo Deleting the zone %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } else { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
