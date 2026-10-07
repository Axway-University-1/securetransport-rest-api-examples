@echo off
REM ==============================================================================
REM Script Name: 21.configurations_loginSettings_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the login settings, using the
REM `/configurations/loginSettings` endpoint: how end users and administrators
REM authenticate - password, certificate, single sign-on, LDAP, SiteMinder.
REM
REM Usage:
REM 21.configurations_loginSettings_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/loginSettings" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  end users: password {0}, SSO {1}, LDAP {2}' -f $r.requirePassword, $r.userSSO, $r.ldapOption; '  administrators: certificate {0}, SSO {1}' -f $r.adminCertificateOption, $r.adminSSO"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
