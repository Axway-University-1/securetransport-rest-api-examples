@echo off
REM ==============================================================================
REM Script Name: 01.sessions_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the sessions open on the server now, using the `/sessions` endpoint.
REM It demonstrates:
REM - Listing every session, one line each: id, user, protocol, client host, the command it runs, when it began
REM - Keeping the sessions of one protocol (FTP, HTTP or SSH), and those of one user
REM
REM Usage:
REM 01.sessions_GET.bat [TYPE [USER]]
REM
REM   TYPE  all, FTP, HTTP or SSH, in capitals (default: all)
REM   USER  show only the sessions of this user name, exactly as written (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to keeps the sessions asked for and print one line each, in place of jq.
REM - A session exists only while a client is connected, so on a quiet server the list is empty: `[]`.
REM   To see one, log in as a test account over FTP, SFTP or the EndUser API and keep the connection open.
REM - Confirmed directly: the answer is a plain array, not {resultSet, result}. Each session has id, userName, host,
REM   protocol, userClass, currentTransferBandwidth, command, sessionCreationTime, nodeIp and serverName. The reference
REM   spells the bandwidth field `currentTransferBandwith` and lists only FTP and HTTP as protocols; the server writes
REM   it with the d, and SSH sessions are listed too.
REM - Confirmed directly: `type=` is IGNORED by the server (type=SSH, type=XX and type=ftp all answer every session),
REM   so this script sends it and then keeps the matching ones itself. The protocol is matched exactly, in capitals.
REM   There is no filter for a user: the one here is applied by this script, as is `limit` when it is 0 or negative
REM   (400 "Limit should be a positive integer"); `limit=abc` is a bare 404. `fields=` works (an unknown field
REM   gives `{ }` for each session) and `localDaemonReturn=` made no difference with any value.
REM - Confirmed directly: the list is NOT stable from one call to the next. Right after clients connect, or
REM   while they stay connected, a call can lack sessions that are open (one protocol of several), or answer `[]`;
REM   the next call has them again. Read it again before acting on it, and never decide from a single read that a
REM   session is gone.
REM - Confirmed directly: an id is `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>`, long, and hex. `command` is
REM   IDLE for an FTP session that is doing nothing, STOR while it uploads, and empty for HTTP and SSH. The user
REM   of a session is the account's login name. `sessionCreationTime` is an RFC 2822 date; `nodeIp` holds a
REM   newline ("Local \n (address)"); `currentTransferBandwidth` is -1 when nothing is being transferred.
REM - Confirmed directly: the administrator's own API login is not a session of this list (the list was empty with
REM   one open), and 05.sessions_statistics_userClass_GET.bat counts the same sessions.
REM - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sessions
SET TYPE=%~1
IF "%TYPE%"=="" SET TYPE=all
SET USER_NAME=%~2
IF NOT "%~3"=="" GOTO usage
IF "%TYPE%"=="all" GOTO type_ok
IF "%TYPE%"=="FTP" GOTO type_ok
IF "%TYPE%"=="HTTP" GOTO type_ok
IF "%TYPE%"=="SSH" GOTO type_ok
:usage
echo Usage: 01.sessions_GET.bat [TYPE [USER]]   ^(TYPE is all, FTP, HTTP or SSH^)
EXIT /B 2
:type_ok
SET RESPONSE_FILE=%TEMP%\sessions_%RANDOM%.json

SET HTTP_CODE=
IF "%TYPE%"=="all" (
    FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
) ELSE (
    FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET -G "%MAIN_URL%" --data-urlencode "type=%TYPE%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
)
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

powershell -NoProfile -Command "$all = ConvertFrom-Json (Get-Content -Raw $env:RESPONSE_FILE); $s = @(@($all) | Where-Object { $_ -and ($env:TYPE -ceq 'all' -or $_.protocol -ceq $env:TYPE) -and (-not $env:USER_NAME -or $_.userName -ceq $env:USER_NAME) }); 'Sessions: {0}' -f $s.Count; ''; 'Id, user, protocol, client host, command, started:'; foreach ($x in $s) { $c = if ($x.command) { $x.command } else { '-' }; '  {0}  {1}  {2}  {3}  {4}  {5}' -f $x.id, $x.userName, $x.protocol, $x.host, $c, $x.sessionCreationTime }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
