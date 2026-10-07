@echo off
REM ==============================================================================
REM Script Name: 02.logs_server_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one server log entry using the `/logs/server/{id}` endpoint: the message in
REM full, with the thread, the class and line that wrote it, and a stack trace if there is one.
REM
REM Usage:
REM 02.logs_server_id_GET.bat [ID]
REM
REM   ID  the entry's id, as 01.logs_server_GET.bat could show it under id.urlrepresentation
REM       (default: the newest entry)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The id is the urlrepresentation of the id object: Base64 of "Id [mConfigurationId=...,
REM   mEventId=..., mTimestamp=...]". An id that is not Base64 of that form answers 400 "Invalid
REM   format for log entry ID"; a well formed one that is not there answers 404.
REM - The newest entry is found by asking for the last one: the log is oldest first.
REM - PowerShell is used to find the newest entry and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/server
SET "ENTRY_ID=%~1"
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
IF NOT "%ENTRY_ID%"=="" GOTO have_id
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO SET TOTAL=%%N
IF NOT DEFINED TOTAL SET TOTAL=0
SET OFFSET=0
IF %TOTAL% GTR 0 SET /A OFFSET=%TOTAL%-1
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" --data-urlencode "limit=1" --data-urlencode "offset=%OFFSET%" --data-urlencode "fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.result) { $r.result[0].id.urlrepresentation }"') DO SET "ENTRY_ID=%%I"
IF "%ENTRY_ID%"=="" (
    echo The server log is empty.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
:have_id

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENTRY_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the entry ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; $m = ($r.message -replace '[\r\n\t]', ' '); if ($m.Length -gt 200) { $m = $m.Substring(0, 200) }; '  {0}  {1}  {2}  thread {3}' -f $r.time, $r.level, $r.component, (& $d $r.thread); '  ' + $m; '  written by {0}.{1} line {2}' -f (& $d $r.className), (& $d $r.method), (& $d $r.line)"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
