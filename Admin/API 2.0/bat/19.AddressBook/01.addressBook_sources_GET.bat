@echo off
REM ==============================================================================
REM Script Name: 01.addressBook_sources_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the address book sources using the `/addressBook/sources`
REM endpoint: where the end users' address book finds the people they share
REM with - the local accounts, an LDAP directory, or a custom source. It
REM demonstrates:
REM - Listing every source
REM - Filtering by type and by whether a source is enabled
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.addressBook_sources_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - type is LOCAL, LDAP or CUSTOM. name and parentGroup filter too.
REM - A server comes with its sources; the API has no POST or DELETE for them,
REM   only reading and changing (see 04 and 05 in this folder).
REM - PowerShell is used to print one source per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/addressBook/sources
SET RESPONSE_FILE=%TEMP%\sources_%RANDOM%.json

echo Every address book source:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The LDAP sources only:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?type=LDAP" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
echo The enabled ones, one line each: id, type, name, group:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?enabled=true&fields=id,type,name,parentGroup" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { '  {0}  {1}  {2}  {3}' -f $s.id, $s.type, $s.name, $s.parentGroup }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
