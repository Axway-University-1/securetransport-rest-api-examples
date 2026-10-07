@echo off
REM ==============================================================================
REM Script Name: 20.configurations_sentinel_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script turns off reporting to Axway Sentinel, using the
REM `/configurations/sentinel` endpoint with PUT: it reads the settings, sets
REM enabled and heartbeatEnabled to false, and sends the whole settings back.
REM
REM Usage:
REM 20.configurations_sentinel_PUT.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The host, port and the other settings stay, ready to turn on again.
REM - Confirmed directly: once a host is set, the endpoint refuses an empty one,
REM   "host must not be null or empty", even with reporting off, and then any
REM   change at all. Turn reporting off first, then set the options behind it with
REM   04.configurations_options_PUT.bat: AxwaySentinel.RemoteHost.host and
REM   AxwaySentinel.OverflowFile.path to an empty string, and
REM   AxwaySentinel.RemoteHost.port and AxwaySentinel.Heartbeat.delay to their
REM   values before.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to edit the settings, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json
SET CHECK_FIELD=enabled

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/sentinel" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET BEFORE=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.PSObject.Properties.Name -contains $env:CHECK_FIELD) { ([string]$r.($env:CHECK_FIELD)).ToLower() } } catch { }"') DO SET BEFORE=%%V
IF NOT DEFINED BEFORE (
    echo Could not read the Sentinel settings.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
echo enabled is now %BEFORE%.
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.enabled = $false; $r.heartbeatEnabled = $false; $r | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/sentinel" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
