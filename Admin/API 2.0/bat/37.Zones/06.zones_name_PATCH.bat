@echo off
REM ==============================================================================
REM Script Name: 06.zones_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script partially updates a zone using the `/zones/{name}` endpoint.
REM It demonstrates:
REM - A JSON Patch that replaces one field, the description, and leaves the rest of the zone as it is
REM
REM Usage:
REM 06.zones_name_PATCH.bat NAME [DESCRIPTION]
REM
REM   NAME         the zone to change (required: never run it on `Private`)
REM   DESCRIPTION  the new description (default "Patched by the examples"), at most 255 characters
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the description before, to put it back with.
REM - Confirmed directly: a success answers 204, with no body. Unlike a PUT, a PATCH leaves everything it does not name as it was. `replace` worked
REM   on a description that was null, and `remove` set it back to null; `add` on a field that is set worked too. Other paths that worked:
REM   `/publicURLPrefix`, `/isDefault` (true makes it the only default zone, and false turns it off again), `/edges/0/notes`, `/edges/0/protocols/0/port`,
REM   `/edges/-` (add an edge, which needs a `title`) and `remove` of `/edges/1`. A path that does not exist is 400 `Missing field "nope"`; `/name` is
REM   400 "Specified zone name does not match the one in the zone object."; `/edges/0/edgeId` answers 204 and is ignored; an empty patch is 204; an unknown zone is 404.
REM   Take care with an edge: a patch of its `title` makes the server treat it as another edge, and a proxy password it had saved is gone (`isUsePassword`
REM   false); two edges with the same title are 500 "Database error updating zone."; a second protocol of the same kind on an edge is accepted.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 06.zones_name_PATCH.bat NAME [DESCRIPTION]
    EXIT /B 2
)
SET DESCRIPTION=%~2
IF "%DESCRIPTION%"=="" SET "DESCRIPTION=Patched by the examples"
powershell -NoProfile -Command "if ($env:DESCRIPTION.Length -gt 255) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo DESCRIPTION is 255 characters at most.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET ZONE_FILE=%TEMP%\zone_%RANDOM%.json
SET BODY_FILE=%TEMP%\zone_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%?fields=description" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ZONE_FILE%"
powershell -NoProfile -Command "$z = Get-Content -Raw $env:ZONE_FILE | ConvertFrom-Json; 'The description of ' + $env:NAME + ' is now: ' + $(if ($z.description) { $z.description } else { '(none)' })"
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -InputObject @(@{ op = 'replace'; path = '/description'; value = $env:DESCRIPTION })))"

echo Setting it to: %DESCRIPTION%
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%ZONE_FILE%" DEL "%ZONE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
