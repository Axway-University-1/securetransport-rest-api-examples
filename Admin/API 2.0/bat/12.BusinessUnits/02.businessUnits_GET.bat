@echo off
REM ==============================================================================
REM Script Name: 02.businessUnits_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the business units using the `/businessUnits` endpoint.
REM It demonstrates:
REM - Listing them, a page at a time
REM - Searching by name, with the * wildcard
REM - The units nested under another one, with parent=
REM
REM Usage:
REM 02.businessUnits_GET.bat [PATTERN [PARENT]]
REM
REM   PATTERN  a name, * matches anything (default *)
REM   PARENT   list the units nested under this one (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: baseFolder= is ignored, every value gives every unit.
REM - Confirmed directly: parent is always null in an answer, even for a nested
REM   unit; businessUnitHierarchy, parent/child, and
REM   metadata.links.parentBusinessUnit are where the nesting shows. parent= as a
REM   filter does work.
REM - PowerShell is used to print one unit per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=*
SET PARENT=%~2
SET RESPONSE_FILE=%TEMP%\bus_%RANDOM%.json

echo The first 5 business units:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=5&offset=0" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The units named %PATTERN%: hierarchy, base folder:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%PATTERN%" ^
  --data-urlencode "fields=businessUnitHierarchy,baseFolder" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($b in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  {0}  {1}' -f $b.businessUnitHierarchy, $b.baseFolder }"

IF "%PARENT%"=="" GOTO done
echo.
echo The units nested under %PARENT%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "parent=%PARENT%" ^
  --data-urlencode "fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($b in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  ' + $b.name }"

:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
