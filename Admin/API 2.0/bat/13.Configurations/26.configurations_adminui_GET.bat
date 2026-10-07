@echo off
REM ==============================================================================
REM Script Name: 26.configurations_adminui_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the Admin UI configuration, using the
REM `/configurations/adminui` endpoint: which pages and dashboard cards the
REM Admin UI shows.
REM
REM Usage:
REM 26.configurations_adminui_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - adminUiConfig is a JSON document inside a string; jq's fromjson reads it.
REM - PUT and PATCH exist, for the Admin UI's own use only.
REM - PowerShell is used to print the pages, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/adminui" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $c = $r.adminUiConfig | ConvertFrom-Json; foreach ($p in $c.pages.PSObject.Properties) { $s = if ($p.Value.enabledPage -eq $false) { 'hidden' } else { 'shown' }; '  {0}: {1}' -f $p.Name, $s }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
