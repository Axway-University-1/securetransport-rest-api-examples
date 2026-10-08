@echo off
REM ==============================================================================
REM Script Name: 07.routes_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes routes using the `/routes/{id}` endpoint.
REM A route is deleted by its id, not its name, so it demonstrates:
REM - Looking up the id of a route by name
REM - Deleting the composite routes first, and only then the simple routes they
REM   run, since a simple route in use cannot be deleted
REM - Printing the HTTP code of each delete, and exiting 1 when the server refuses one
REM
REM Usage:
REM 07.routes_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up the routes 02 to 05 in this folder create for the account
REM   "john". Only ever point it at routes you created.
REM - Composite route names are only unique within an account, so a composite
REM   route is matched by its account as well as its name.
REM - The route templates are left in place. 08.RouteTemplates created them, and 08.RouteTemplates/03.routes_DELETE_all.bat removes them.
REM - The name filter ignores case and takes a * wildcard, so the exact name is picked out of what comes back. Two simple routes may share a
REM   name, so a name that matches more than one route (for a composite route: more than one of the account) is NOT deleted, and the exit code is 1.
REM - A route the server refuses to delete (a simple route that another route still runs, for one: 400 "Route is in use.") makes the exit
REM   code 1, and the next ones are still tried.
REM - PowerShell is used to read the ids out of the responses, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Route is not found.". Two simple routes may share a
REM   name (03.routes_POST_simple_compress.bat run twice makes two, each 201), so a name that matches two is refused here, with exit 1: remove one by its id.
REM - Exit codes: 0 when every route was deleted or was not there, 1 when the server refuses a lookup or a delete, or a name is ambiguous.
REM   It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

IF NOT "%~1"=="" (
    echo Usage: 07.routes_id_DELETE.bat
    EXIT /B 2
)

SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\routes_%RANDOM%.json
SET FAILED=0

CALL :delete_route COMPOSITE CompositeRoute_Subscription
CALL :delete_route COMPOSITE CompositeRoute_WithExtension
CALL :delete_route COMPOSITE CompositeRoute_WithoutExtension

CALL :delete_route SIMPLE SimpleRoute_Compress
CALL :delete_route SIMPLE SimpleRoute_Decompress
CALL :delete_route SIMPLE SimpleRouteName

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM delete_route TYPE NAME: looks the route up by type and exact name (for a composite route: of the account too) and deletes it
REM ------------------------------------------------------------------------------
:delete_route
SET ROUTE_TYPE=%1
SET ROUTE_NAME=%2
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/routes" --data-urlencode "type=%ROUTE_TYPE%" --data-urlencode "name=%ROUTE_NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not look up the %ROUTE_TYPE% route '%ROUTE_NAME%': HTTP %HTTP_CODE%
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
REM The name filter ignores case and takes a * wildcard, so only the routes with exactly this name count
SET FOUND=0
SET ROUTE_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null -and $_.name -ceq $env:ROUTE_NAME -and ($env:ROUTE_TYPE -eq 'SIMPLE' -or $_.account -ceq $env:ACCOUNT) }) | ForEach-Object { $_.id }"') DO (
    SET /A FOUND+=1
    SET ROUTE_ID=%%I
)
IF "%FOUND%"=="0" (
    echo There is no %ROUTE_TYPE% route '%ROUTE_NAME%'.
    EXIT /B 0
)
IF NOT "%FOUND%"=="1" (
    echo There are %FOUND% %ROUTE_TYPE% routes named '%ROUTE_NAME%'; none deleted.
    SET FAILED=1
    EXIT /B 0
)

echo Deleting the %ROUTE_TYPE% route '%ROUTE_NAME%' (%ROUTE_ID%)...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ROUTE_ID)"') DO SET ROUTE_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/routes/%ROUTE_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
echo Deleted the %ROUTE_TYPE% route '%ROUTE_NAME%'.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
