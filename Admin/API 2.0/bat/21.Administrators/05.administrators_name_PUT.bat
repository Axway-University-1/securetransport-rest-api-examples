@echo off
REM ==============================================================================
REM Script Name: 05.administrators_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces an administrator, using the `/administrators/{name}`
REM endpoint with PUT: it reads the administrator, unlocks it, and sends the
REM whole administrator back.
REM
REM Usage:
REM 05.administrators_name_PUT.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - 06.administrators_name_PATCH.bat locks it; this unlocks it.
REM - The read-only parts are left out of what is sent: metadata, and the API
REM   keys, which have their own endpoint (08 to 10 in this folder).
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to edit the administrator, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=%~1
IF "%ADMIN%"=="" SET ADMIN=example_admin
SET ADMIN_FILE=%TEMP%\admin_%RANDOM%.json
SET BODY_FILE=%TEMP%\admin_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ADMIN%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ADMIN_FILE%"
SET FOUND=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:ADMIN_FILE | ConvertFrom-Json).loginName } catch { }"') DO SET FOUND=%%N
IF NOT DEFINED FOUND (
    echo There is no administrator %ADMIN%.
    IF EXIST "%ADMIN_FILE%" DEL "%ADMIN_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$a = Get-Content -Raw $env:ADMIN_FILE | ConvertFrom-Json; $a.locked = $false; $a.PSObject.Properties.Remove('metadata'); $a.PSObject.Properties.Remove('apiKeys'); $a | ConvertTo-Json -Compress -Depth 10 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Unlocking %ADMIN%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ADMIN%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%ADMIN_FILE%" DEL "%ADMIN_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
