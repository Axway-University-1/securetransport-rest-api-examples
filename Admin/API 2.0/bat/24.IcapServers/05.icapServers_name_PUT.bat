@echo off
REM ==============================================================================
REM Script Name: 05.icapServers_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces an ICAP server using the `/icapServers/{name}` endpoint with PUT:
REM it reads the server, changes the largest file it is sent (maxSize), and sends the
REM whole server back.
REM
REM Usage:
REM 05.icapServers_name_PUT.bat [NAME [MAX_MB]]
REM
REM   NAME    the server (default example_icap)
REM   MAX_MB  the largest file, in MB; 0 is unlimited (default 10)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put back with.
REM - Confirmed directly: a PUT whose body has another basicSettings.name RENAMES the
REM   server (the old name is gone). This script sets the name back to NAME, so it
REM   cannot rename.
REM - Confirmed directly: the whole of basicSettings, with maxSize and previewSize, is
REM   required; a body without previewSize answers 400. metadata is read back and may
REM   be sent, or dropped: this script drops it.
REM - A name that does not exist answers 400 "does not exist".
REM - PowerShell is used to URL-encode the name and edit the server, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_icap
SET MAX_MB=%~2
IF "%MAX_MB%"=="" SET MAX_MB=10
ECHO %MAX_MB%| FINDSTR /R /X "[0-9][0-9]*" >NUL || (
    echo MAX_MB must be a whole number: %MAX_MB%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\icap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\icap_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET BEFORE=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.basicSettings.name) { $r.basicSettings.maxSize } } catch { }"') DO SET BEFORE=%%V
IF NOT DEFINED BEFORE (
    echo There is no ICAP server %NAME%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
echo maxSize of %NAME% is now %BEFORE% MB.
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.PSObject.Properties.Remove('metadata'); $r.basicSettings.name = $env:NAME; $r.basicSettings.maxSize = [int]$env:MAX_MB; [IO.File]::WriteAllText($env:BODY_FILE, ($r | ConvertTo-Json -Compress -Depth 10))"

echo Setting it to %MAX_MB% MB...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
