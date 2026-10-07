@echo off
REM ==============================================================================
REM Script Name: 30.configurations_fileArchiving_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces the file archiving settings, using the
REM `/configurations/fileArchiving` endpoint with PUT: it reads them, changes the
REM largest file archived (maximumFileSizeAllowedToArchive), and sends the whole
REM settings back.
REM
REM Usage:
REM 30.configurations_fileArchiving_PUT.bat MAX_MB
REM
REM   MAX_MB  the largest file archived, in MB
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put back with.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to edit the settings, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET MAX_MB=%~1
ECHO %MAX_MB%| FINDSTR /R /X "[0-9][0-9]*" >NUL || (
    echo Usage: 30.configurations_fileArchiving_PUT.bat MAX_MB
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json
SET CHECK_FIELD=maximumFileSizeAllowedToArchive

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/fileArchiving" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET BEFORE=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.PSObject.Properties.Name -contains $env:CHECK_FIELD) { ([string]$r.($env:CHECK_FIELD)).ToLower() } } catch { }"') DO SET BEFORE=%%V
IF NOT DEFINED BEFORE (
    echo Could not read the file archiving settings.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
echo maximumFileSizeAllowedToArchive is now %BEFORE%.
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.maximumFileSizeAllowedToArchive = [int]$env:MAX_MB; $r | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/fileArchiving" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
