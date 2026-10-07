@echo off
REM ==============================================================================
REM Script Name: 03.logs_audit_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tries to change the description of an audit log entry using the
REM `/logs/audit/{id}` endpoint with PUT, and reads the entry back to show what happened.
REM
REM Usage:
REM 03.logs_audit_id_PUT.bat ID [DESCRIPTION]
REM
REM   ID           the entry's id (see 01.logs_audit_GET.bat, 02.logs_audit_id_GET.bat)
REM   DESCRIPTION  the text to try (default "Changed by 03.logs_audit_id_PUT.bat")
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the server ANSWERS 204, as for a change, but the description stays what
REM   it was: on entries of every kind, for old ones and new, with the whole entry sent back or
REM   only the required fields. The audit trail cannot be edited through this call. This script
REM   prints the description before and after, so that it is plain.
REM - The body needs id, configurationId, operationType and dateModified; this script sends back
REM   what it read, with the new description. A body without them answers 400 "must not be null".
REM - The id is required, though nothing is changed.
REM - PowerShell is used to URL-encode the id and edit the entry, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/audit
SET "ENTRY_ID=%~1"
SET "DESCRIPTION=%~2"
IF "%DESCRIPTION%"=="" SET "DESCRIPTION=Changed by 03.logs_audit_id_PUT.bat"
IF "%ENTRY_ID%"=="" (
    echo Usage: 03.logs_audit_id_PUT.bat ID [DESCRIPTION]
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\logs_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ENTRY_ID)"') DO SET ENCODED=%%E

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET FOUND=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.operationType) { 'yes' } } catch { }"') DO SET FOUND=%%V
IF NOT DEFINED FOUND (
    echo There is no audit log entry %ENTRY_ID%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The description is now: ' + $r.description; $r.PSObject.Properties.Remove('metadata'); $r.description = $env:DESCRIPTION; [IO.File]::WriteAllText($env:BODY_FILE, ($r | ConvertTo-Json -Compress -Depth 10))"
FOR /F "delims=" %%B IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).description"') DO SET "BEFORE=%%B"

echo Trying to set it to: %DESCRIPTION%
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The description is now: ' + $r.description; if ($r.description -eq $env:BEFORE -and $env:DESCRIPTION -ne $env:BEFORE) { 'It did not change: the audit log cannot be edited.' }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
