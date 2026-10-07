@echo off
REM ==============================================================================
REM Script Name: 09.routes_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a route, using the `/routes/{id}` endpoint with PUT: it reads
REM the route, changes its description, and sends the whole route back, steps
REM included.
REM
REM Usage:
REM 09.routes_id_PUT.bat NAME [DESCRIPTION]
REM
REM   NAME         the route (it must be the only one with that name)
REM   DESCRIPTION  the new description (default: Changed by 09.routes_id_PUT.bat)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the description before, to put it back with.
REM - PUT replaces the whole route: a body with the name and type only answers 204 and
REM   silently removes every step. That is why the route is read first, and sent back
REM   with only the description changed. metadata, the read-only links, is left out.
REM - Confirmed directly: a success answers 204, with no body. The steps keep their ids
REM   when they are sent back with them. A route can be renamed by changing `name`, and
REM   two simple routes may share a name. A body with another route's id or another
REM   `type` is refused, 400. An unknown id is 404, a body without `type` or
REM   `conditionType` 400.
REM - PowerShell is used to read the id and edit the route, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 09.routes_id_PUT.bat NAME [DESCRIPTION]
    EXIT /B 2
)
SET DESCRIPTION=%~2
IF "%DESCRIPTION%"=="" SET DESCRIPTION=Changed by 09.routes_id_PUT.bat
SET LOOKUP_FILE=%TEMP%\route_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET ROUTE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET ROUTE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% routes named %NAME%; this script acts on exactly one.
    EXIT /B 1
)
SET NONE_TEXT=(none)
SET ROUTE_FILE=%TEMP%\route_%RANDOM%.json
SET BODY_FILE=%TEMP%\route_body_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ROUTE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ROUTE_FILE%"
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$d = (Get-Content -Raw $env:ROUTE_FILE | ConvertFrom-Json).description; if ($d) { $d } else { $env:NONE_TEXT }"') DO echo The description of %NAME% is now: %%D
powershell -NoProfile -Command "$r = Get-Content -Raw $env:ROUTE_FILE | ConvertFrom-Json; $r.description = $env:DESCRIPTION; $r.PSObject.Properties.Remove('metadata'); $r | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to: %DESCRIPTION%
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ROUTE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%ROUTE_FILE%" DEL "%ROUTE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
