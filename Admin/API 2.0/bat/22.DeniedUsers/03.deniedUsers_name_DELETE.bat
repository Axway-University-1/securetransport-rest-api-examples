@echo off
REM ==============================================================================
REM Script Name: 03.deniedUsers_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script removes a login name from the denied users using the
REM `/deniedUsers/{name}` endpoint: the name can log in again.
REM
REM Usage:
REM 03.deniedUsers_name_DELETE.bat [LOGIN_NAME]
REM
REM   LOGIN_NAME  the name to unblock (default example_denied)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This unblocks a login name: only remove the ones you added. The list also
REM   holds the names the server blocks by default.
REM - The name is case sensitive here, though the list's loginName= filter is not.
REM - Confirmed directly: a name that is not in the list answers 400 "No denied user
REM   found with login name", not 404. There is no GET or HEAD on one name: both
REM   answer 405; read the list with 01.deniedUsers_GET.bat.
REM - The name goes into the path URL-encoded once, with jq's @uri, so a name with a
REM   space works.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/deniedUsers
SET LOGIN_NAME=%~1
IF "%LOGIN_NAME%"=="" SET LOGIN_NAME=example_denied
IF "%LOGIN_NAME: =%"=="" (
    echo LOGIN_NAME must not be empty.
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\denied_response_%RANDOM%.json

FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:LOGIN_NAME)"') DO SET ENCODED=%%E

echo Unblocking %LOGIN_NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
