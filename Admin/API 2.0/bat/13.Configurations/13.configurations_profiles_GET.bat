@echo off
REM ==============================================================================
REM Script Name: 13.configurations_profiles_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the configuration profiles, using the
REM `/configurations/profiles` endpoint: the server's own configuration and the
REM default configuration of each protocol.
REM
REM Usage:
REM 13.configurations_profiles_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - node is the server or edge the profile applies to; protocol is null for the
REM   server's own profile.
REM - PowerShell is used to print one profile per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

echo Configuration profiles: id, name, protocol, active:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/profiles" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $pr = $p.protocol; if (-not $pr) { $pr = '-' }; $a = $p.active; if ($null -eq $a) { $a = '-' } else { $a = ([string]$a).ToLower() }; '  {0}  {1}  {2}  {3}' -f $p.id, $p.name, $pr, $a }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
