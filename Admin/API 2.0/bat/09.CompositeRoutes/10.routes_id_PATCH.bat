@echo off
REM ==============================================================================
REM Script Name: 10.routes_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a route's step, using the `/routes/{id}`
REM endpoint with PATCH: a JSON Patch document that enables or disables the first
REM step of a given type. Unlike PUT (09.routes_id_PUT.bat), it sends only what
REM changes. A step is addressed by its position, so the script reads the route and
REM finds the position first.
REM
REM Usage:
REM 10.routes_id_PATCH.bat NAME STEP_TYPE [STATUS]
REM
REM   NAME       the route (it must be the only one with that name)
REM   STEP_TYPE  the type of the step, for example Compress or SendToPartner
REM   STATUS     ENABLED or DISABLED (default DISABLED)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the status before, to put it back with.
REM - Confirmed directly: the path is /steps/<position>/status. A step's id cannot be used
REM   in its place (400 "Can't reference field ... on array"), a position past the end is
REM   400 "Array index N is out of bounds", and a status other than ENABLED or DISABLED
REM   is 400. A success answers 204, with no body.
REM - Other things a patch of a route did, confirmed directly: `add` at /steps/- appends a
REM   step, `add` at /steps/1 inserts one in the middle and the steps' precedingStep links
REM   follow, `remove` at /steps/N deletes one, `replace` works on a description that is
REM   null, `type` and `id` are read only (400), and a composite route's `routeTemplate`
REM   cannot be changed (400).
REM - PowerShell is used to read the id and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes
SET NAME=%~1
SET STEP_TYPE=%~2
IF "%NAME%"=="" GOTO :usage
IF "%STEP_TYPE%"=="" GOTO :usage
SET STATUS=%~3
IF "%STATUS%"=="" SET STATUS=DISABLED
IF NOT "%STATUS%"=="ENABLED" IF NOT "%STATUS%"=="DISABLED" (
    echo STATUS is ENABLED or DISABLED, not %STATUS%.
    EXIT /B 2
)
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
SET ROUTE_FILE=%TEMP%\route_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ROUTE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ROUTE_FILE%"
REM The position of the first step of that type, and its status now
SET POSITION=none
SET BEFORE=
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$s = @((Get-Content -Raw $env:ROUTE_FILE | ConvertFrom-Json).steps); $i = 0; foreach ($x in $s) { if ($x.type -eq $env:STEP_TYPE) { [string]$i + [char]32 + $x.status; break }; $i++ }"') DO (
    SET POSITION=%%A
    SET BEFORE=%%B
)
IF EXIST "%ROUTE_FILE%" DEL "%ROUTE_FILE%"
IF "%POSITION%"=="none" (
    echo The route %NAME% has no step of type %STEP_TYPE%.
    EXIT /B 1
)
echo The %STEP_TYPE% step of %NAME% is at position %POSITION%, and is %BEFORE%.

echo Setting it to %STATUS%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ROUTE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/steps/%POSITION%/status\",\"value\":\"%STATUS%\"}]"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 10.routes_id_PATCH.bat NAME STEP_TYPE [STATUS]
EXIT /B 2
