@echo off
REM ==============================================================================
REM Script Name: 13.servers_operations_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script starts or stops a protocol server, using the `/servers/operations` endpoint.
REM A stop refuses the clients of that server until it is started again.
REM It demonstrates:
REM - A guard: nothing is sent unless the server and the operation are given and, for a stop, the confirmation word as well
REM - Starting one server, with the status of the server and of its daemon printed first and the command that undoes it
REM - Starting every server that is found not running, and then every daemon that is not running (--all-stopped)
REM - The HTTP code, and the result the server gives for each server
REM
REM Usage:
REM 13.servers_operations_POST.bat SERVER start
REM 13.servers_operations_POST.bat SERVER stop stop-the-SERVER-server [TIMEOUT]
REM 13.servers_operations_POST.bat --all-stopped start-all-stopped-servers
REM
REM   SERVER    the name of the server, as GET /servers lists it ("Ssh Default"): quote it when it has a space
REM   stop-the-SERVER-server
REM             the confirmation of a stop: this exact word, with the server's name in it (stop-the-Ssh Default-server). Without
REM             it, or with any other word, the script prints this usage, sends NOTHING and exits 2. A start needs none
REM   TIMEOUT   seconds to wait for the server's answer, a whole number (optional; the reference says 150 or more, and 150 is its default)
REM   --all-stopped start-all-stopped-servers
REM             starts every server that is not running and then every daemon that is not running: it needs its own word, as it
REM             starts what an administrator may have stopped on purpose
REM
REM Risk: disruptive - stops and starts protocol servers: their clients are refused while one is stopped
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - THIS CAN STOP A SERVER of the whole system. There is no default server and no environment variable that stands in for the
REM   confirmation word: the server and the operation are arguments, and a stop needs `stop-the-SERVER-server` as well. The arguments are
REM   checked before anything is sent: a bad one exits 2. It used to start every stopped server and daemon when run bare; that is
REM   `--all-stopped` now, with its own word.
REM - It reads the servers first, prints the server's state and the state of the daemon of its protocol, and the command that undoes the
REM   operation. A server that is not there is a stop of nothing: exit 1, no operation sent. A server already in the state asked for (a start
REM   of one that is active, a stop of one that is not) is left alone: exit 0, no operation sent.
REM - A server needs the daemon of its protocol: when that one is not running the script says so and points at
REM   05.daemons_operations_POST.bat, and still sends the start. Starting a server right after its daemon can fail for a moment and
REM   succeed on a retry (see st-api-gotchas).
REM - `--all-stopped` keeps the order of the older script: the servers first, then the daemons. The as2 server and daemon of a lab
REM   that has AS2 disabled cannot start (see below), so on such a lab it ends with exit 1 by design.
REM - THIS WAS NOT RUN against a server while the script was made safe: no server of the lab was started or stopped by this change. The
REM   status codes and the answer are from the reference and from what check 23 recorded earlier. What WAS confirmed directly, with names
REM   that do not exist (nothing started or stopped): the answer is 200 with `{"serverStatuses": [{"serverName", "message", "isSuccessful"}]}`
REM   whether or not it worked, so a 200 proves nothing and this script reads `isSuccessful`; an unknown server is 200 with `isSuccessful`
REM   false and "Server with name X does not exist."; a start with no `serverName` is 400 "Specify at least one server name to start.";
REM   an `operation` that is not start or stop is 400 (`must match "(?i)start|(?i)stop"`: the pattern ignores case, which was not tried). From earlier work: a start of
REM   the as2 daemon is 200 with `isSuccessful` false when its default server is not enabled. This script is tested offline against a stub `curl`.
REM - PowerShell is used to read the state, encode nothing by hand and build the output, in place of jq.
REM - Exit codes: 0 when the server answered 200 and every result is successful (or there was nothing to do), 1 when it refuses, a
REM   result is not successful or the server is not there, 2 when an argument is missing or wrong, or the confirmation word is not
REM   given (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0
SET "USAGE=Usage: 13.servers_operations_POST.bat SERVER start, or SERVER stop stop-the-SERVER-server [TIMEOUT], or --all-stopped start-all-stopped-servers"
SET "ALL_WORD=start-all-stopped-servers"

SET "SERVER=%~1"
SET "OPERATION=%~2"
SET "TIMEOUT="
IF "%SERVER%"=="--all-stopped" GOTO check_all
IF "%SERVER%"=="" (
    echo SERVER is the name of a server ^(or --all-stopped^). Nothing was sent.
    GOTO usage
)
IF "%OPERATION%"=="start" (
    IF NOT "%~3"=="" GOTO usage
    GOTO checked
)
IF NOT "%OPERATION%"=="stop" (
    echo OPERATION is start or stop. Nothing was sent.
    GOTO usage
)
SET "CONFIRMATION=stop-the-%SERVER%-server"
IF NOT "%~3"=="%CONFIRMATION%" (
    echo This stops the server %SERVER%: its clients are refused until it is started again.
    echo Nothing was sent. To go on, give the word %CONFIRMATION% as the third argument.
    GOTO usage
)
SET "TIMEOUT=%~4"
IF NOT "%TIMEOUT%"=="" (
    FOR /F "delims=0123456789" %%X IN ("%TIMEOUT%") DO (
        echo TIMEOUT is a whole number of seconds. Nothing was sent.
        GOTO usage
    )
)
IF NOT "%~5"=="" GOTO usage
GOTO checked

:check_all
IF "%~2"=="%ALL_WORD%" IF "%~3"=="" GOTO checked
echo This starts every server and daemon that is not running, including those an administrator stopped on purpose.
echo Nothing was sent. To go on, give the word %ALL_WORD% as the second argument.
GOTO usage

:usage
echo %USAGE%
EXIT /B 2

:checked
SET RESPONSE_FILE=%TEMP%\server_response_%RANDOM%.json
SET SERVERS_FILE=%TEMP%\server_list_%RANDOM%.txt
SET NAMES_FILE=%TEMP%\server_names_%RANDOM%.txt
SET DAEMONS_FILE=%TEMP%\server_daemons_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%SERVERS_FILE%" DEL "%SERVERS_FILE%"
IF EXIST "%NAMES_FILE%" DEL "%NAMES_FILE%"
IF EXIST "%DAEMONS_FILE%" DEL "%DAEMONS_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM The work; the exit code of the script is the one of this subroutine
REM ------------------------------------------------------------------------------
:main
SET FAILED=0
IF "%SERVER%"=="--all-stopped" GOTO all_stopped

echo Reading the servers...
CALL :list_servers
IF ERRORLEVEL 1 EXIT /B 1
SET ENTRY=
FOR /F "delims=" %%L IN ('powershell -NoProfile -Command "Get-Content $env:SERVERS_FILE | ForEach-Object { $f = $_ -split [char]9; if ($f[0] -ceq $env:SERVER) { $f[1] + [char]32 + $f[2] } } | Select-Object -First 1"') DO SET ENTRY=%%L
IF "%ENTRY%"=="" (
    echo There is no server named '%SERVER%'. No operation was sent.
    EXIT /B 1
)
FOR /F "tokens=1,2" %%A IN ("%ENTRY%") DO (
    SET IS_ACTIVE=%%A
    SET PROTOCOL=%%B
)
CALL :read_daemons
IF ERRORLEVEL 1 EXIT /B 1
SET DAEMON_STATUS=unknown
FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "$s = (Get-Content -Raw $env:DAEMONS_FILE | ConvertFrom-Json).($env:PROTOCOL + 'Status'); if ($s) { $s } else { 'unknown' }"') DO SET DAEMON_STATUS=%%S
SET STATE=not active
IF "%IS_ACTIVE%"=="true" SET STATE=active
echo The %PROTOCOL% server '%SERVER%' is now: %STATE%. Its %PROTOCOL% daemon is: %DAEMON_STATUS%
IF "%OPERATION%"=="stop" GOTO one_stop

echo To stop it again: 13.servers_operations_POST.bat "%SERVER%" stop "stop-the-%SERVER%-server"
IF "%IS_ACTIVE%"=="true" (
    echo It is already active: nothing to start. No operation was sent.
    EXIT /B 0
)
IF NOT "%DAEMON_STATUS%"=="Running" echo The %PROTOCOL% daemon is not running, and a server needs it: 05.daemons_operations_POST.bat %PROTOCOL% start
GOTO one_send

:one_stop
echo To bring it back: 13.servers_operations_POST.bat "%SERVER%" start
IF NOT "%IS_ACTIVE%"=="true" (
    echo It is not active: nothing to stop. No operation was sent.
    EXIT /B 0
)

:one_send
CALL :server_operation "%SERVER%" %OPERATION% %TIMEOUT%
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM --all-stopped: the servers that are not running, then the daemons that are not running
:all_stopped
echo Getting the list of servers...
CALL :list_servers
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "@(Get-Content $env:SERVERS_FILE).Count"') DO echo Found %%N servers
powershell -NoProfile -Command "Get-Content $env:SERVERS_FILE | ForEach-Object { $f = $_ -split [char]9; if ($f[1] -eq 'false') { $f[0] } } | Set-Content -Path $env:NAMES_FILE"
IF EXIST "%NAMES_FILE%" FOR /F "usebackq delims=" %%N IN ("%NAMES_FILE%") DO CALL :start_stopped "%%N"
powershell -NoProfile -Command "Get-Content $env:SERVERS_FILE | ForEach-Object { $f = $_ -split [char]9; if ($f[1] -eq 'true') { 'Server: ' + $f[0] + ' is running' } }"

echo Getting the list of daemons...
CALL :read_daemons
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "Get-Content -Raw $env:DAEMONS_FILE | ConvertFrom-Json | ConvertTo-Json -Compress"
FOR %%D IN (ssh as2 pesit ftp http) DO CALL :daemon_step %%D
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Starts the server named in %1, which is not running
REM ------------------------------------------------------------------------------
:start_stopped
echo Server: %~1 is not running
CALL :server_operation "%~1" start
IF ERRORLEVEL 1 SET FAILED=1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Starts the daemon named in %1 when its status is Not running
REM ------------------------------------------------------------------------------
:daemon_step
SET DAEMON=%1
SET DSTATUS=unknown
FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "$s = (Get-Content -Raw $env:DAEMONS_FILE | ConvertFrom-Json).($env:DAEMON + 'Status'); if ($s) { $s } else { 'unknown' }"') DO SET DSTATUS=%%S
IF NOT "%DSTATUS%"=="Not running" (
    echo Daemon %DAEMON% is %DSTATUS%
    EXIT /B 0
)
echo Starting the %DAEMON% daemon...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X POST "%MAIN_URL%/daemons/operations" --data-urlencode "operation=start" --data-urlencode "daemon=%DAEMON%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $list = @($r.daemonOperationResults | Where-Object { $_ -ne $null }); if ($list.Count -eq 0) { $list = @($r) }; $bad = 0; foreach ($d in $list) { '{0} {1} (successful: {2})' -f $d.daemon, $d.message, ([string]$d.isSuccessful).ToLower(); if ($null -ne $d.isSuccessful -and -not $d.isSuccessful) { $bad++ } }; if ($bad -gt 0) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 SET FAILED=1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Writes every server into SERVERS_FILE, one per line: the name, a tab, true or false for isActive, a tab, the protocol; 1 when it cannot
REM ------------------------------------------------------------------------------
:list_servers
IF EXIST "%SERVERS_FILE%" DEL "%SERVERS_FILE%"
SET OFFSET=0
:list_page
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/servers" --data-urlencode "fields=serverName,isActive" --data-urlencode "limit=200" --data-urlencode "offset=%OFFSET%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the servers: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
SET PAGE_COUNT=0
FOR /F %%N IN ('powershell -NoProfile -Command "$l = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null }); $l | ForEach-Object { Add-Content -Path $env:SERVERS_FILE -Value ($_.serverName + [char]9 + ([string]$_.isActive).ToLower() + [char]9 + $_.protocol) }; $l.Count"') DO SET PAGE_COUNT=%%N
IF %PAGE_COUNT% LSS 200 (
    IF NOT EXIST "%SERVERS_FILE%" type nul > "%SERVERS_FILE%"
    EXIT /B 0
)
SET /A OFFSET+=200
GOTO list_page

REM ------------------------------------------------------------------------------
REM Reads the daemons into DAEMONS_FILE (a copy, as RESPONSE_FILE is reused by the calls that follow); 1 when it cannot
REM ------------------------------------------------------------------------------
:read_daemons
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/daemons" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the daemons: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
COPY /Y "%RESPONSE_FILE%" "%DAEMONS_FILE%" >nul
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Performs operation %2 on the server %1, with the timeout %3 when there is one: prints the code and each result; 1 on any failure
REM ------------------------------------------------------------------------------
:server_operation
SET "OP_NAME=%~1"
SET "OP_OPERATION=%~2"
SET "OP_TIMEOUT=%~3"
SET TIMEOUT_ARG=
IF NOT "%OP_TIMEOUT%"=="" SET TIMEOUT_ARG=--data-urlencode "timeout=%OP_TIMEOUT%"
echo Performing '%OP_OPERATION%' on the server '%OP_NAME%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X POST "%MAIN_URL%/servers/operations" --data-urlencode "serverName=%OP_NAME%" --data-urlencode "operation=%OP_OPERATION%" %TIMEOUT_ARG% -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_error
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $l = @($r.serverStatuses | Where-Object { $_ -ne $null }); if ($l.Count -eq 0) { 'The answer has no result for the server:'; Get-Content -Raw $env:RESPONSE_FILE; exit 1 }; $bad = 0; foreach ($s in $l) { '{0} {1} (successful: {2})' -f $s.serverName, $s.message, ([string]$s.isSuccessful).ToLower(); if ($s.isSuccessful -ne $true) { $bad++ } }; if ($bad -gt 0) { exit 1 } else { exit 0 }"
EXIT /B %ERRORLEVEL%

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
