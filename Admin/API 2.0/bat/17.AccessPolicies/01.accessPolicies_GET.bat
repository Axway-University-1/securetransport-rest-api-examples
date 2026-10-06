@echo off
REM ==============================================================================
REM Script Name: 01.accessPolicies_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the database access policies using the `/accessPolicies`
REM endpoint. They are the rules of the embedded PostgreSQL database's
REM pg_hba.conf file: which connections, to which database, as which user, from
REM which address, are allowed and how they authenticate. It demonstrates:
REM - Listing every rule, in the order the database reads them
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.accessPolicies_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - Confirmed directly: the answer is a plain JSON array, not the
REM   {"result": [...]} the API reference shows.
REM - A rule's id is its line in the file. The database uses the first rule that
REM   matches a connection, so the order matters.
REM - PowerShell is used to print one rule per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json

echo Every database access policy, in the order they are read:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The same, one line each: id, connection type, database, user, address, method:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET ^
  "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies?fields=id,connectionType,database,user,address,authMethod" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $all) { $a = $p.address; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}  {3}  {4}  {5}' -f $p.id, $p.connectionType, $p.database, $p.user, $a, $p.authMethod }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
