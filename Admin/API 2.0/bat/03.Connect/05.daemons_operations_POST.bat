@echo off
REM ==============================================================================
REM Script Name: 05.daemons_operations_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script starts or stops a daemon (ftp, http, ssh, as2 or pesit), using the `/daemons/operations` endpoint.
REM A stop takes every protocol that daemon serves down with it: its clients are refused until it is started again.
REM It demonstrates:
REM - A guard: nothing is sent unless the daemon and the operation are given and, for a stop, the confirmation word as well
REM - A graceful stop (the default), which lets the connections in progress finish within a timeout, and an immediate one
REM - The status of the daemon is printed first, with the command that brings it back
REM - The HTTP code, and the result the server gives for each daemon
REM
REM Usage:
REM 05.daemons_operations_POST.bat DAEMON start
REM 05.daemons_operations_POST.bat DAEMON stop stop-the-DAEMON-daemon [GRACEFUL [TIMEOUT]]
REM
REM   DAEMON        ftp, http, ssh, as2 or pesit
REM   stop-the-DAEMON-daemon
REM                 the confirmation of a stop: this exact word, with the daemon's name in it (stop-the-ssh-daemon). Without it, or
REM                 with any other word, the script prints this usage, sends NOTHING and exits 2. A start needs none
REM   GRACEFUL      true (default) lets the connections in progress finish; false stops at once
REM   TIMEOUT       seconds to wait for them, a whole number, only with GRACEFUL true (optional; the daemon's own timeout when left out)
REM
REM Risk: disruptive - stops and starts daemons: every protocol on them goes down meanwhile
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - THIS STOPS A DAEMON of the whole server. There is no default daemon and no environment variable that stands in for the confirmation word:
REM   the daemon and the operation are arguments, and a stop needs `stop-the-DAEMON-daemon` as well. The arguments are checked before anything is sent: a bad one exits 2.
REM - It prints the daemon's status first, and the command that undoes the operation. Starting a daemon again with this script is the way back; a protocol server
REM   that was running on it may then need its own start (13.servers_operations_POST.bat starts every server and daemon found not running).
REM - A graceful stop with a timeout keeps running on the server after this script is gone: never kill the script before it returns, and do not start the daemon again
REM   while a delayed stop may still be pending (see st-api-gotchas).
REM - THIS WAS NOT RUN against a server while the script was made safe: no daemon of the lab was stopped or started, by this change. What follows is from the reference and from
REM   what check 23 recorded earlier (its docstring and st-api-gotchas): the answer is 200 with `daemonOperationResults`, a list of `{daemon, message, isSuccessful}`; a start of the
REM   as2 daemon is 200 with `isSuccessful` false and "Can not start AS2 daemon - the default server As2 Default is not enabled." whatever the status code says. This script
REM   prints every result and exits 1 when one has `isSuccessful` false, or when the status is not 200. It is tested offline against a stub `curl`.
REM - PowerShell is used to read the status and the answer, in place of jq.
REM - Exit codes: 0 when the server answered 200 and every daemon result is successful, 1 when it refuses or a result is not successful, 2 when an argument is missing or
REM   wrong, or the confirmation word of a stop is not given (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons
SET DAEMON=%~1
SET OPERATION=%~2
SET USAGE=Usage: 05.daemons_operations_POST.bat DAEMON start, or DAEMON stop stop-the-DAEMON-daemon [GRACEFUL [TIMEOUT]]

SET DAEMON_OK=
FOR %%D IN (ftp http ssh as2 pesit) DO IF "%DAEMON%"=="%%D" SET DAEMON_OK=yes
IF NOT "%DAEMON_OK%"=="yes" (
    echo DAEMON is ftp, http, ssh, as2 or pesit. Nothing was sent.
    echo %USAGE%
    EXIT /B 2
)
IF "%OPERATION%"=="start" (
    IF NOT "%~3"=="" GOTO usage
    SET QUERY=operation=start^&daemon=%DAEMON%
    GOTO checked
)
IF NOT "%OPERATION%"=="stop" (
    echo OPERATION is start or stop. Nothing was sent.
    echo %USAGE%
    EXIT /B 2
)
SET CONFIRMATION=stop-the-%DAEMON%-daemon
IF NOT "%~3"=="%CONFIRMATION%" (
    echo This stops the %DAEMON% daemon of the whole server: its clients are refused until it is started again.
    echo Nothing was sent. To go on, give the word %CONFIRMATION% as the third argument.
    echo %USAGE%
    EXIT /B 2
)
SET GRACEFUL=%~4
IF "%GRACEFUL%"=="" SET GRACEFUL=true
SET TIMEOUT=%~5
IF NOT "%GRACEFUL%"=="true" IF NOT "%GRACEFUL%"=="false" GOTO usage
IF NOT "%TIMEOUT%"=="" (
    FOR /F "delims=0123456789" %%X IN ("%TIMEOUT%") DO GOTO usage
    IF NOT "%GRACEFUL%"=="true" GOTO usage
)
IF NOT "%~6"=="" GOTO usage
SET QUERY=operation=stop^&daemon=%DAEMON%^&graceful=%GRACEFUL%
IF NOT "%TIMEOUT%"=="" SET QUERY=%QUERY%^&timeout=%TIMEOUT%
:checked

SET RESPONSE_FILE=%TEMP%\daemon_response_%RANDOM%.json

echo Reading the status of the daemons...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the daemons: HTTP %HTTP_CODE%
    GOTO refused
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $s = $r.($env:DAEMON + 'Status'); if (-not $s) { $s = 'unknown' }; 'The {0} daemon is now: {1}' -f $env:DAEMON, $s"
IF "%OPERATION%"=="stop" (
    echo To bring it back: 05.daemons_operations_POST.bat %DAEMON% start
) ELSE (
    echo To stop it again: 05.daemons_operations_POST.bat %DAEMON% stop stop-the-%DAEMON%-daemon
)

echo Performing '%OPERATION%' on the '%DAEMON%' daemon...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/operations?%QUERY%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" GOTO refused
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $list = @($r.daemonOperationResults | Where-Object { $_ -ne $null }); if ($list.Count -eq 0) { $list = @($r) }; $bad = 0; foreach ($d in $list) { '{0} {1} (successful: {2})' -f $d.daemon, $d.message, ([string]$d.isSuccessful).ToLower(); if ($null -ne $d.isSuccessful -and -not $d.isSuccessful) { $bad++ } }; if ($bad -gt 0) { exit 1 } else { exit 0 }"
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
