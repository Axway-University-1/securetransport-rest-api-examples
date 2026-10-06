@echo off
REM ==============================================================================
REM Script Name: 08.administrators_name_apiKeys_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates an API key for an administrator, using the
REM `/administrators/{name}/api-keys` endpoint. An API key authenticates every
REM request on its own, in the SECURETRANSPORT-API-KEY header: no login, no
REM session, no password - for scripts and integrations.
REM
REM Usage:
REM 08.administrators_name_apiKeys_POST.bat [DAYS [PERMISSIONS]]
REM
REM   DAYS         how many days the key is valid (default 30)
REM   PERMISSIONS  read, write and delete, comma separated (default read).
REM                read is GET and HEAD; write is POST, PUT and PATCH; delete is
REM                DELETE.
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The administrator is example_admin, which 02.administrators_POST.bat creates.
REM - The key itself is in this answer only. Keep it: the server stores only a
REM   hash, and the list (09.administrators_name_apiKeys_GET.bat) never shows it.
REM - Confirmed directly: an administrator holds at most 2 keys (a third answers
REM   409); validityDays or expiresAt (RFC 2822), not both (400).
REM - 10.administrators_name_apiKeys_keyId_DELETE.bat revokes keys.
REM - PowerShell is used to build the body and read the key, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin
SET DAYS=%~1
IF "%DAYS%"=="" SET DAYS=30
SET PERMISSIONS=%~2
IF "%PERMISSIONS%"=="" SET PERMISSIONS=read
ECHO %DAYS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo DAYS must be a whole number: %DAYS%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\apikey_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\apikey_response_%RANDOM%.json

powershell -NoProfile -Command "@{ validityDays=[int]$env:DAYS; permissions=@($env:PERMISSIONS -split ',') } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Creating a %DAYS% day key for %ADMIN%, permissions %PERMISSIONS%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%ADMIN%/api-keys" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="201" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$k = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Key id {0}, valid until {1}, permissions {2}' -f $k.id, $k.expiresAt, ($k.permissions -join ', '); 'The key, shown this once: ' + $k.key"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
