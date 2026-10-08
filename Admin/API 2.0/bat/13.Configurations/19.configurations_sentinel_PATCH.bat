@echo off
REM ==============================================================================
REM Script Name: 19.configurations_sentinel_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script turns on reporting to Axway Sentinel, using the
REM `/configurations/sentinel` endpoint with PATCH: the Sentinel host and port,
REM a heartbeat, and the file events go to while Sentinel cannot be reached.
REM
REM Usage:
REM 19.configurations_sentinel_PATCH.bat HOST [PORT]
REM
REM   HOST  the Sentinel server
REM   PORT  its port (default 1305)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the settings before, to put back with
REM   20.configurations_sentinel_PUT.bat.
REM - Confirmed directly: turning reporting on needs overflowFilePath, a file on
REM   the ST server; without it, 400 "overflowFilePath must not be null or
REM   empty."
REM - Confirmed directly: the server connects at once and sends XML events, a
REM   HEARTBEAT every heartbeatDelay seconds. tests/integration/lib/dummy_servers.py
REM   has a TcpSink that can stand in for Sentinel.
REM - Confirmed directly: once a host is set, the endpoint refuses an empty one,
REM   "host must not be null or empty", even with reporting off, and then any
REM   change at all. Turn reporting off first, then set the options behind it with
REM   04.configurations_options_PUT.bat: AxwaySentinel.RemoteHost.host and
REM   AxwaySentinel.OverflowFile.path to an empty string, and
REM   AxwaySentinel.RemoteHost.port and AxwaySentinel.Heartbeat.delay to their
REM   values before.
REM - PowerShell is used to build the patch and print the settings, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET HOST=%~1
SET PORT=%~2
IF "%PORT%"=="" SET PORT=1305
IF "%HOST%"=="" GOTO usage
ECHO %PORT%| FINDSTR /R /X "[0-9][0-9]*" >NUL || GOTO usage
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

echo Before:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/sentinel" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  ' + ([ordered]@{ enabled = $r.enabled; host = $r.host; port = $r.port; heartbeatEnabled = $r.heartbeatEnabled; heartbeatDelay = $r.heartbeatDelay; overflowFilePath = $r.overflowFilePath } | ConvertTo-Json -Compress)"

powershell -NoProfile -Command "ConvertTo-Json -Compress -Depth 5 -InputObject @(@{op='replace'; path='/host'; value=$env:HOST}, @{op='replace'; path='/port'; value=[int]$env:PORT}, @{op='replace'; path='/overflowFilePath'; value='/tmp/st_sentinel_overflow.dat'}, @{op='replace'; path='/heartbeatEnabled'; value=$true}, @{op='replace'; path='/heartbeatDelay'; value=30}, @{op='replace'; path='/enabled'; value=$true}) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Reporting to Sentinel at %HOST%:%PORT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/sentinel" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
GOTO :EOF

:usage
echo Usage: 19.configurations_sentinel_PATCH.bat HOST [PORT]
EXIT /B 2
