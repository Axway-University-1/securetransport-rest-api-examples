@echo off
REM ==============================================================================
REM Script Name: 05.sessions_statistics_userClass_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads how many sessions are open for each user class, using the
REM `/sessions/statistics/userClass` endpoint: the count by protocol on the whole server (and on this
REM node), the bandwidth in use and the limit.
REM
REM Usage:
REM 05.sessions_statistics_userClass_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print one line per user class, in place of jq.
REM - Confirmed directly: the answer is a plain array of the two classes the server always has, VirtClass (the
REM   accounts the server holds itself, which is every account made through the API) and RealClass (system users).
REM   It is NEVER empty, unlike the session list: with no client connected every count is 0.
REM - Confirmed directly: the counts follow the sessions as they open and close. With an FTP and an HTTP session of one
REM   test account open, VirtClass read total 2, ftp 1, http 1; after the FTP one was ended it read 1. An SSH session
REM   is counted as ssh. `globalLoggedInCounters` is the cluster, `localLoggedInCounters` this node: the same on a
REM   standalone server.
REM - Confirmed directly: `maxAllowed` is `unlimited` (or a number as text), `instantaneousFTPBandwidth` was `N/A`, and
REM   `bandwidthUsageStats` (inbound, outbound) 0 even while a client uploaded. `fields=userClass` keeps one key per class.
REM - Exit codes: 0 when the server answered 200, 1 when it refuses.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sessions/statistics/userClass
SET RESPONSE_FILE=%TEMP%\sessions_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

powershell -NoProfile -Command "$all = ConvertFrom-Json (Get-Content -Raw $env:RESPONSE_FILE); $s = @(@($all) | Where-Object { $_ }); 'Sessions by user class: {0} classes' -f $s.Count; ''; 'User class, sessions on the server (ftp, http, ssh), on this node, bandwidth in and out, the most allowed:'; foreach ($x in $s) { $g = $x.globalLoggedInCounters; '  {0}  {1} sessions (ftp {2}, http {3}, ssh {4})  here {5}  in {6}, out {7}  max {8}' -f $x.userClass, $g.total, $g.ftp, $g.http, $g.ssh, $x.localLoggedInCounters.total, $x.bandwidthUsageStats.inbound, $x.bandwidthUsageStats.outbound, $x.maxAllowed }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
