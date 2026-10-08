@echo off
REM ==============================================================================
REM Script Name: 04.sessions_statistics_bandwidth_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the bandwidth the open sessions use, per login name, using the
REM `/sessions/statistics/bandwidth` endpoint: the sessions of each, their inbound and outbound rate, and
REM the limit they are allowed.
REM
REM Usage:
REM 04.sessions_statistics_bandwidth_GET.bat [LIMIT]
REM
REM   LIMIT  the most login names to return, a positive whole number (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print one line per login name, in place of jq.
REM - Confirmed directly: the answer is a plain array, and EMPTY (`[]`) on the lab while an FTP client uploaded 6 MB
REM   and while sessions of several protocols sat idle: the lab has no bandwidth limit set, and this list seems
REM   to hold only users that have one. The shape below (loginName, bandwidthUsageStats and maxAllowedBandwidth with
REM   inbound and outbound, sessions with total, http, ftp and ssh) is the reference's and was not seen on the lab.
REM - Confirmed directly: `limit=0` is 400 "limit should be a positive integer"; `fields=` is accepted.
REM   A POST is 405.
REM - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sessions/statistics/bandwidth
SET LIMIT=%~1
IF NOT "%~2"=="" GOTO usage
IF "%LIMIT%"=="" GOTO args_ok
powershell -NoProfile -Command "if ($env:LIMIT -notmatch '^[0-9]+$' -or [int64]$env:LIMIT -lt 1) { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
GOTO args_ok
:usage
echo Usage: 04.sessions_statistics_bandwidth_GET.bat [LIMIT]   ^(LIMIT is a positive whole number^)
EXIT /B 2
:args_ok
SET RESPONSE_FILE=%TEMP%\sessions_%RANDOM%.json

SET HTTP_CODE=
IF "%LIMIT%"=="" (
    FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
) ELSE (
    FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET -G "%MAIN_URL%" --data-urlencode "limit=%LIMIT%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
)
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

powershell -NoProfile -Command "function N($v, $d) { if ($null -eq $v) { $d } else { $v } }; $all = ConvertFrom-Json (Get-Content -Raw $env:RESPONSE_FILE); $s = @(@($all) | Where-Object { $_ }); 'Login names using bandwidth: {0}' -f $s.Count; ''; 'Login name, sessions, inbound and outbound now, the most allowed:'; foreach ($x in $s) { '  {0}  {1} sessions (ftp {2}, http {3}, ssh {4})  in {5}, out {6}  max in {7}, out {8}' -f $x.loginName, (N $x.sessions.total 0), (N $x.sessions.ftp 0), (N $x.sessions.http 0), (N $x.sessions.ssh 0), (N $x.bandwidthUsageStats.inbound 0), (N $x.bandwidthUsageStats.outbound 0), (N $x.maxAllowedBandwidth.inbound '-'), (N $x.maxAllowedBandwidth.outbound '-') }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
