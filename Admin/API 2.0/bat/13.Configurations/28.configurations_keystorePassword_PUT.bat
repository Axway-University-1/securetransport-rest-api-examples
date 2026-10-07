@echo off
REM ==============================================================================
REM Script Name: 28.configurations_keystorePassword_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes the password of the server's keystore, using the
REM `/configurations/keystorePassword` endpoint with PUT: the old password, and
REM the new one twice.
REM
REM Usage:
REM 28.configurations_keystorePassword_PUT.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - NOT RUN on the shared lab these examples were checked against: it changes
REM   the whole server, and cannot simply be undone. Its request is checked
REM   offline, against a stub.
REM - OLD_KEYSTORE_PASSWORD and NEW_KEYSTORE_PASSWORD are read from the
REM   environment, so export them first:
REM     SET OLD_KEYSTORE_PASSWORD=the current password
REM     SET NEW_KEYSTORE_PASSWORD=the new password
REM - Keep the new password safe: the keystore holds the server's private keys.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
IF "%OLD_KEYSTORE_PASSWORD%"=="" GOTO need
IF "%NEW_KEYSTORE_PASSWORD%"=="" GOTO need
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "@{ oldPassword=$env:OLD_KEYSTORE_PASSWORD; newPassword=$env:NEW_KEYSTORE_PASSWORD; confirmPassword=$env:NEW_KEYSTORE_PASSWORD } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Changing the keystore password...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/keystorePassword" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
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
GOTO :EOF

:need
echo Set OLD_KEYSTORE_PASSWORD and NEW_KEYSTORE_PASSWORD first.
EXIT /B 2
