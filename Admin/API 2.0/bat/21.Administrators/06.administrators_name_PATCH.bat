@echo off
REM ==============================================================================
REM Script Name: 06.administrators_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script locks an administrator, using the `/administrators/{name}`
REM endpoint with PATCH: a JSON Patch document that replaces locked. A locked
REM administrator cannot log in.
REM
REM Usage:
REM 06.administrators_name_PATCH.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - 05.administrators_name_PUT.bat unlocks it again.
REM - Confirmed directly: a success answers 204, with no body.
REM - Never point it at the administrator you log in as: the script refuses it (exit 2, nothing sent), whatever the case of the name.
REM - PowerShell is used to URL-encode the login name and build the patch, in place of jq.
REM - Confirmed directly: an administrator that does not exist is 404 "Admin not found - X".
REM - Exit codes: 0 when it was locked (204), 1 when the server refuses, 2 when the name is the one logged in as (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET "ADMIN=%~1"
IF "%ADMIN%"=="" SET ADMIN=example_admin
IF /I "%ADMIN%"=="%ST_USER%" (
    echo That is the administrator this script logs in as. Not locking it.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ADMIN)"') DO SET "ENCODED=%%E"
SET BODY_FILE=%TEMP%\admin_patch_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\admin_response_%RANDOM%.json

powershell -NoProfile -Command "ConvertTo-Json -Compress -InputObject @(@{ op='replace'; path='/locked'; value=$true }) | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Locking %ADMIN%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
