@echo off
REM ==============================================================================
REM Script Name: 07.configurations_options_groups_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the groups of Server Configuration Options, using the
REM `/configurations/options/groups` endpoint: sets of related options the
REM Admin UI shows together, like the SMTP or the S3 storage profile settings.
REM
REM Usage:
REM 07.configurations_options_groups_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is a plain array, not {result: [...]}.
REM - 08.configurations_options_groups_name_GET.bat reads one group.
REM - PowerShell is used to print one group per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

echo The option groups:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options/groups" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($g in @($r)) { '  {0}: {1}' -f $g.name, $g.description }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
