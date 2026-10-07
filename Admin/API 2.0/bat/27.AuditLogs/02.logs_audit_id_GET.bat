@echo off
REM ==============================================================================
REM Script Name: 02.logs_audit_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one audit log entry using the `/logs/audit/{id}` endpoint: the change, who
REM made it, from where, and a text of the object as it was.
REM
REM Usage:
REM 02.logs_audit_id_GET.bat [ID]
REM
REM   ID  the entry's id (default: the newest entry)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The id is a plain string, unlike the composite ids of the transfer and server logs.
REM - objectString is the audited object written out, which can be long; for a created or changed
REM   object it shows the values it was given.
REM - A missing id answers 404 "Audit log entry with Id ... not found".
REM - PowerShell is used to look the newest entry up and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/audit
SET "ENTRY_ID=%~1"
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
IF NOT "%ENTRY_ID%"=="" GOTO have_id
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.result) { $r.result[0].id }"') DO SET "ENTRY_ID=%%I"
IF "%ENTRY_ID%"=="" (
    echo The audit log is empty.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
:have_id
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ENTRY_ID)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; '  {0} {1} {2}, {3}' -f $r.operationType, $r.objectType, (& $d $r.objectName), $r.dateModified; $a = if ($r.userAgent) { $r.userAgent } else { 'no user agent' }; '  by {0} from {1} ({2})' -f (& $d $r.userName), (& $d $r.remoteAddress), $a; $t = if ($r.description) { $r.description } else { 'no description' }; '  ' + $t"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
