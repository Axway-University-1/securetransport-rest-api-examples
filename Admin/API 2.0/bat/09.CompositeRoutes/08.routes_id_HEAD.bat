@echo off
REM ==============================================================================
REM Script Name: 08.routes_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a route exists, using the `/routes/{id}` endpoint with
REM HEAD: 200 when it does, 404 when it does not. The path takes the route's id, so
REM the script looks the id up by name first.
REM
REM Usage:
REM 08.routes_id_HEAD.bat [NAME]
REM
REM   NAME  the route (default SimpleRoute_Compress, which
REM         03.routes_POST_simple_compress.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The route is looked up by name, and must be the only one with that name.
REM - Confirmed directly: HEAD answers 200 for a route of any type (simple, template or
REM   composite) and 404, with no body, for an id that does not exist.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes
SET NAME=%~1
IF "%NAME%"=="" SET NAME=SimpleRoute_Compress
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

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ROUTE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The route %NAME% exists, id %ROUTE_ID%.
) ELSE (
    echo The route %NAME%, id %ROUTE_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
