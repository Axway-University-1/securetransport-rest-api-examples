@echo off
REM ==============================================================================
REM Script Name: 09.configurations_logging_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the logging configuration options, using the
REM `/configurations/logging` endpoint: the log4j configuration of each part of
REM the server (Admin, SSH, FTP, HTTP, AS2, PeSIT, Transaction Manager, ...).
REM
REM Usage:
REM 09.configurations_logging_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Each logging option belongs to a configuration profile; profileId says which.
REM   13.configurations_profiles_GET.bat lists the profiles.
REM - PowerShell is used to print one option per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

echo Logging options: name, profile, propagation status:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/logging" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($o in $r.result) { $s = $o.propagationStatus; if (-not $s) { $s = '-' }; '  {0}  {1}  {2}' -f $o.name, $o.profileId, $s }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
