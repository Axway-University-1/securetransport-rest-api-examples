@echo off
REM ==============================================================================
REM Script Name: 04.logs_audit_GET_csv.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script exports the audit log as a CSV file using the `/logs/audit` endpoint, asking for
REM text/csv in place of JSON.
REM
REM Usage:
REM 04.logs_audit_GET_csv.bat [OUTPUT [HOURS]]
REM
REM   OUTPUT  the file to write (default audit_log.csv)
REM   HOURS   how far back, in whole hours (default 24)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the same endpoint answers text/csv when asked, with a header row:
REM   User Name, Remote Host, User Agent, Date Modified, Object Type, Object Identifier, Object
REM   String, Id, Object Zone, Object Zone Node, Object Name, Operation Type, Node Name,
REM   Description. Asking for application/xml answers 406.
REM - At most 1000 entries are asked for; narrow HOURS for a busy server.
REM - The file is written to the current folder, and holds object texts: handle it as the audit
REM   log itself.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/audit
SET "OUTPUT=%~1"
IF "%OUTPUT%"=="" SET "OUTPUT=audit_log.csv"
SET "HOURS=%~2"
IF "%HOURS%"=="" SET "HOURS=24"
ECHO %HOURS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo HOURS must be a whole number of 1 or more: %HOURS%
    EXIT /B 2
)

echo Exporting the last %HOURS% hour^(s^) to %OUTPUT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" --data-urlencode "duration=%HOURS%" --data-urlencode "limit=1000" -H "accept: text/csv" -H "%REFERER_HEADER%" -o "%OUTPUT%" -w "%%{http_code}"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    TYPE "%OUTPUT%"
    echo.
    DEL "%OUTPUT%"
    EXIT /B 1
)
FOR /F %%N IN ('find /c /v "" ^< "%OUTPUT%"') DO echo Wrote %OUTPUT%: %%N line^(s^) including the header.
powershell -NoProfile -Command "'Its header: ' + (Get-Content -TotalCount 1 -LiteralPath $env:OUTPUT)"
