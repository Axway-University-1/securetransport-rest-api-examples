@echo off
REM ==============================================================================
REM Script Name: 09.administrators_name_apiKeys_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists an administrator's API keys, using the
REM `/administrators/{name}/api-keys` endpoint, and shows a call made with one.
REM It demonstrates:
REM - The keys' ids, expiry, permissions and last use
REM - Authenticating with the SECURETRANSPORT-API-KEY header alone
REM
REM Usage:
REM 09.administrators_name_apiKeys_GET.bat [KEY]
REM
REM   KEY  a key 08.administrators_name_apiKeys_POST.bat printed, to call
REM        GET /myself with it (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The administrator is example_admin, which 02.administrators_POST.bat creates.
REM - The list never holds the keys themselves, only their ids.
REM - Confirmed directly: with a key, GET /myself answers as the key's
REM   administrator, with no -u and no session; a method the key's permissions do
REM   not cover answers 403, "This API key does not have permission to perform
REM   DELETE requests."; a revoked or expired key answers 401, in plain text,
REM   "Authentication required."
REM - PowerShell is used to print one key per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin
SET KEY=%~1
SET RESPONSE_FILE=%TEMP%\apikeys_%RANDOM%.json

echo The API keys of %ADMIN%: id, valid until, permissions, last used:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ADMIN%/api-keys" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($k in @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json)) { $u = $k.lastAccessedAt; if (-not $u) { $u = 'never' }; $e = ''; if ($k.expired) { $e = '  EXPIRED' }; '  {0}  {1}  {2}  {3}{4}' -f $k.id, $k.expiresAt, ($k.permissions -join ','), $u, $e }"

IF "%KEY%"=="" GOTO done
echo.
echo Who the key logs in as, with no password and no session:
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "SECURETRANSPORT-API-KEY: %KEY%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo   The key was refused ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$m = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0}, role {1}' -f $m.loginName, $m.roleName"

:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
