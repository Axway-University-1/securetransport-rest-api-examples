@echo off
REM ==============================================================================
REM Script Name: 23.configurations_loginSettings_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one login setting, using the
REM `/configurations/loginSettings` endpoint with PATCH: whether end users must
REM give a password (requirePassword).
REM
REM Usage:
REM 23.configurations_loginSettings_PATCH.bat [VALUE]
REM
REM   VALUE  optional, required or requiredForUserClasses (default optional);
REM          requiredForUserClasses also needs requirePasswordUserClasses
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put back with.
REM - Confirmed directly: the whole settings are validated on every change. On a
REM   server whose settings are already inconsistent - certificateIssuer "other"
REM   with no adminCertificateFileOrPath - any PATCH or PUT answers 400 "You must
REM   specify adminCertificateFileOrPath when certificateIssuer is set to
REM   other.", even one that changes nothing.
REM - These settings decide who can log in: try changes on a test server first,
REM   and keep a session open to undo them.
REM - PowerShell is used to read the value, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET VALUE=%~1
IF "%VALUE%"=="" SET VALUE=optional
IF NOT "%VALUE%"=="optional" IF NOT "%VALUE%"=="required" IF NOT "%VALUE%"=="requiredForUserClasses" (
    echo VALUE is optional, required or requiredForUserClasses, not %VALUE%.
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/loginSettings" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'requirePassword is now {0}.' -f $r.requirePassword"

powershell -NoProfile -Command "ConvertTo-Json -Compress -Depth 5 -InputObject @(@{op='replace'; path='/requirePassword'; value=$env:VALUE}) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/loginSettings" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
