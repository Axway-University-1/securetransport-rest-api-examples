@echo off
REM ==============================================================================
REM Script Name: 05.zones_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a zone using the `/zones/{name}` endpoint.
REM It demonstrates:
REM - Reading the zone, changing its description and sending the whole zone back (a PUT replaces it)
REM
REM Usage:
REM 05.zones_name_PUT.bat NAME [DESCRIPTION]
REM
REM   NAME         the zone to replace (required: never run it on `Private`)
REM   DESCRIPTION  the new description (default "Replaced by the examples"), at most 255 characters
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the description before, to put it back with.
REM - Confirmed directly: a success answers 204, with no body. **Send the whole zone back, as this script does.** A PUT replaces the zone, and what is
REM   left out is reset: a body with only `name` and `description` set `publicURLPrefix`, `ssoSpEntityId` and `isDnsResolutionEnabled` back to null/false and
REM   turned `isDefault` off (a default zone is no longer one); but a body with **no `edges` key keeps the edges**, `"edges": []` removes them all, and an edge listed
REM   with only its `title` loses its notes, protocols, proxies, addresses and `enabledProxy`. `name` is required (400 "name must not be null") and must be the name
REM   in the path: another one is 400 "Specified zone name does not match the one in the zone object.", so a PUT cannot rename a zone (nor can a PATCH of
REM   `/name`). An unknown zone is 404 "Zone with name X not found". Sent back as it was read, a zone is kept as it was, the `edgeId`s and a proxy's
REM   `isUsePassword` too, though the password reads `null`. `description` is 255 characters at most (400). An `isDefault` true makes this zone the only default.
REM - PowerShell is used to URL-encode the name and edit the zone, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 05.zones_name_PUT.bat NAME [DESCRIPTION]
    EXIT /B 2
)
SET DESCRIPTION=%~2
IF "%DESCRIPTION%"=="" SET "DESCRIPTION=Replaced by the examples"
powershell -NoProfile -Command "if ($env:DESCRIPTION.Length -gt 255) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo DESCRIPTION is 255 characters at most.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET ZONE_FILE=%TEMP%\zone_%RANDOM%.json
SET BODY_FILE=%TEMP%\zone_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ZONE_FILE%"
SET FOUND=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $z = Get-Content -Raw $env:ZONE_FILE | ConvertFrom-Json; if ($z.name) { 'The description of ' + $z.name + ' is now: ' + $(if ($z.description) { $z.description } else { '(none)' }) } } catch { }"') DO (
    SET FOUND=1
    echo %%V
)
IF NOT DEFINED FOUND (
    echo There is no zone %NAME%.
    IF EXIST "%ZONE_FILE%" DEL "%ZONE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$z = Get-Content -Raw $env:ZONE_FILE | ConvertFrom-Json; $z.description = $env:DESCRIPTION; [IO.File]::WriteAllText($env:BODY_FILE, ($z | ConvertTo-Json -Compress -Depth 20))"

echo Setting it to: %DESCRIPTION%
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%ZONE_FILE%" DEL "%ZONE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
