@echo off
REM ==============================================================================
REM Script Name: 04.icapServers_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one ICAP server using the `/icapServers/{name}` endpoint: its
REM address, type, limits, what it does when it cannot be reached, and its scan policy.
REM
REM Usage:
REM 04.icapServers_name_GET.bat [NAME]
REM
REM   NAME  the server (default example_icap)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The name goes into the path URL-encoded once, with jq's @uri.
REM - The settings come in groups: basicSettings, scanFilteringSettings,
REM   headerSettings, advancedConnectionSettings and advancedIcapSettings.
REM - Confirmed directly: the businessUnits link in metadata, businessUnits?icapServer=,
REM   filters nothing: every value lists every unit. This script reads the units'
REM   enabledIcapServers itself, which is what says whose transfers the server scans
REM   (the first 500 units).
REM - PowerShell is used to URL-encode the name and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_icap
SET RESPONSE_FILE=%TEMP%\icap_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %NAME% ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $b = $r.basicSettings; $e = if ($r.serverEnabled) { 'enabled' } else { 'disabled' }; $d = if ($b.denyOnConnectionError) { 'the transfer is denied' } else { 'the transfer goes on' }; $p = $r.scanFilteringSettings.policyExpression; if (-not $p) { $p = 'none, every transfer' }; '  {0}: {1} {2}, {3}' -f $b.name, $b.type, $b.url, $e; '  files up to {0} MB, preview {1} KB' -f $b.maxSize, $b.previewSize; '  when it cannot be reached: ' + $d; '  scan policy: ' + $p"

echo.
echo Business units that enable it, so whose transfers it scans:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits" --data-urlencode "limit=500" ^
  --data-urlencode "fields=name,enabledIcapServers" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in $r.result) { if (@($u.enabledIcapServers) -contains $env:NAME) { '  ' + $u.name } }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
