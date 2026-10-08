@echo off
REM ==============================================================================
REM Script Name: 01.logs_server_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the server log using the `/logs/server` endpoint: what the protocol servers,
REM the Admin service and the rest wrote while running. It demonstrates:
REM - Counting the entries of the last minutes (fromDate=)
REM - Searching the message, by component (FTPD, SSHD, HTTPD, ...) and by level
REM
REM Usage:
REM 01.logs_server_GET.bat [MINUTES [MESSAGE [COMPONENTS [LEVELS]]]]
REM
REM   MINUTES     how far back to look (default 60)
REM   MESSAGE     text the message must contain (optional)
REM   COMPONENTS  one or more of TM AS2D SSHD SOCKS ADMIN AUDIT FTPD HTTPD PESITD, with commas
REM               between them (optional)
REM   LEVELS      one or more of ALL DEBUG ERROR FATAL INFO TRACE WARN, with commas between them
REM               (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the server log is OLDEST first, the opposite of the audit log, so a
REM   plain limit shows the oldest entries of the server's life. fromDate keeps it to the recent ones.
REM - Confirmed directly: fromDate and endDate are RFC 2822 dates; 2026-10-07 answers 400.
REM - Confirmed directly: component= and level= must be in capitals (ftpd and error find nothing),
REM   and several values are SEPARATE parameters, component=FTPD&component=HTTPD, which this
REM   script sends; a comma list finds nothing. A value that does not exist finds nothing, not 400.
REM - Confirmed directly: message= is a part of the message, with case; * is not a wildcard.
REM - Confirmed directly: accountName= is IGNORED: any value answers every entry. Search the
REM   message for the account name instead.
REM - Confirmed directly (5.5-20260924): what a login writes depends on the protocol. SFTP: component SSHD, INFO
REM   "User NAME login success." and, for a wrong password, INFO (not WARN) "User NAME login failed.". HTTP (EndUser
REM   API): component HTTPD, INFO "User NAME login success."; a failed login names NO account: INFO "Denying access to
REM   unknown user from address ADDRESS" (also for a known account with a wrong password), so search for that text; an
REM   HTTP login also WARNs "virtual user NAME does not have email associated", which is not a failure. FTP: component
REM   FTPD, INFO "virtual user NAME logged in from" and WARN "Failed login for user NAME from". Component TM also
REM   writes INFO "User with login name 'NAME' ... successfully authenticated over SSH, HTTP or FTP".
REM - PowerShell is used to print one entry per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when MINUTES, a component or a level is wrong, or there are more than four arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/server
SET "MINUTES=%~1"
IF "%MINUTES%"=="" SET "MINUTES=60"
SET "MESSAGE=%~2"
SET "COMPONENTS=%~3"
SET "LEVELS=%~4"
IF NOT "%~5"=="" GOTO usage
ECHO %MINUTES%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo MINUTES must be a whole number of 1 or more: %MINUTES%
    EXIT /B 2
)
powershell -NoProfile -Command "foreach ($i in ($env:COMPONENTS -split ',')) { if ($i -and $i -notmatch '^(TM|AS2D|SSHD|SOCKS|ADMIN|AUDIT|FTPD|HTTPD|PESITD)$') { Write-Output ('Unknown component ' + $i + '.'); exit 2 } }"
IF ERRORLEVEL 2 EXIT /B 2
powershell -NoProfile -Command "foreach ($i in ($env:LEVELS -split ',')) { if ($i -and $i -notmatch '^(ALL|DEBUG|ERROR|FATAL|INFO|TRACE|WARN)$') { Write-Output ('Unknown level ' + $i + '.'); exit 2 } }"
IF ERRORLEVEL 2 EXIT /B 2
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json

REM The start, as an RFC 2822 date in GMT; and the query, each value URL-encoded, a component or a level a parameter of its own
FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "[DateTime]::UtcNow.AddMinutes(-[int]$env:MINUTES).ToString(\"ddd, dd MMM yyyy HH:mm:ss\", [Globalization.CultureInfo]::InvariantCulture) + \" GMT\""') DO SET "SINCE=%%S"
FOR /F "delims=" %%Q IN ('powershell -NoProfile -Command "$q = @(\"fromDate=\" + [uri]::EscapeDataString($env:SINCE)); if ($env:MESSAGE) { $q += \"message=\" + [uri]::EscapeDataString($env:MESSAGE) }; foreach ($i in ($env:COMPONENTS -split \",\")) { if ($i) { $q += \"component=\" + $i } }; foreach ($i in ($env:LEVELS -split \",\")) { if ($i) { $q += \"level=\" + $i } }; $q -join [char]38"') DO SET "QUERY=%%Q"
FOR /F "delims=" %%Q IN ('powershell -NoProfile -Command "\"fromDate=\" + [uri]::EscapeDataString($env:SINCE)"') DO SET "SINCE_QUERY=%%Q"

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?%SINCE_QUERY%&limit=1&fields=id"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Server log entries since %SINCE%: %%N

echo.
echo The first 20 that match the filters: time, level, component, message:
SET "URL=%MAIN_URL%?%QUERY%&limit=20&fields=time,level,component,message"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($e in $r.result) { $m = ($e.message -replace '[\r\n\t]', ' '); if ($m.Length -gt 140) { $m = $m.Substring(0, 140) }; '  {0}  {1}  {2}  {3}' -f $e.time, $e.level, $e.component, $m }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 01.logs_server_GET.bat [MINUTES [MESSAGE [COMPONENTS [LEVELS]]]]
EXIT /B 2
