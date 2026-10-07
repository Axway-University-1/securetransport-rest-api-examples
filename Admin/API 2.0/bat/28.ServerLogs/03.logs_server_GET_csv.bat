@echo off
REM ==============================================================================
REM Script Name: 03.logs_server_GET_csv.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script exports the server log as a CSV file using the `/logs/server` endpoint, asking for
REM text/csv in place of JSON.
REM
REM Usage:
REM 03.logs_server_GET_csv.bat [OUTPUT [MINUTES [COMPONENT]]]
REM
REM   OUTPUT     the file to write (default server_log.csv)
REM   MINUTES    how far back, in whole minutes (default 60)
REM   COMPONENT  one component, for example FTPD (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the same endpoint answers text/csv when asked, with a header row: Time,
REM   Level, Component, Thread, Message, Filename, Class, Method, Line, Account or Login, Stack
REM   Trace, Activity, Transferred File, Client Hostname, Edge Hostname, Server Hostname, Node
REM   Name, Session ID, Session Start Time, Transfer ID.
REM - At most 1000 entries are asked for, oldest first; narrow MINUTES for a busy server.
REM - The file is written to the current folder, and holds account names and addresses.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/server
SET "OUTPUT=%~1"
IF "%OUTPUT%"=="" SET "OUTPUT=server_log.csv"
SET "MINUTES=%~2"
IF "%MINUTES%"=="" SET "MINUTES=60"
SET "COMPONENT=%~3"
ECHO %MINUTES%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo MINUTES must be a whole number of 1 or more: %MINUTES%
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:COMPONENT -and $env:COMPONENT -notmatch '^(TM|AS2D|SSHD|SOCKS|ADMIN|AUDIT|FTPD|HTTPD|PESITD)$') { Write-Output ('Unknown component ' + $env:COMPONENT + '.'); exit 2 }"
IF ERRORLEVEL 2 EXIT /B 2

FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "[DateTime]::UtcNow.AddMinutes(-[int]$env:MINUTES).ToString(\"ddd, dd MMM yyyy HH:mm:ss\", [Globalization.CultureInfo]::InvariantCulture) + \" GMT\""') DO SET "SINCE=%%S"
SET FILTER=
IF NOT "%COMPONENT%"=="" SET FILTER=--data-urlencode "component=%COMPONENT%"

echo Exporting the entries since %SINCE% to %OUTPUT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" --data-urlencode "fromDate=%SINCE%" %FILTER% --data-urlencode "limit=1000" -H "accept: text/csv" -H "%REFERER_HEADER%" -o "%OUTPUT%" -w "%%{http_code}"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    TYPE "%OUTPUT%"
    echo.
    DEL "%OUTPUT%"
    EXIT /B 1
)
FOR /F %%N IN ('find /c /v "" ^< "%OUTPUT%"') DO echo Wrote %OUTPUT%: %%N line^(s^) including the header.
powershell -NoProfile -Command "'Its header: ' + (Get-Content -TotalCount 1 -LiteralPath $env:OUTPUT)"
