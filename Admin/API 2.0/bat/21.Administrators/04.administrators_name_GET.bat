@echo off
REM ==============================================================================
REM Script Name: 04.administrators_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads an administrator, using the `/administrators/{name}`
REM endpoint: the role, the parent, the rights the role gives, the password and
REM login times, and the API keys.
REM
REM Usage:
REM 04.administrators_name_GET.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The password itself never comes back: password is empty.
REM - PowerShell is used to URL-encode the login name and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET "ADMIN=%~1"
IF "%ADMIN%"=="" SET ADMIN=example_admin
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ADMIN)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\admin_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %ADMIN% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = $a.parent; if (-not $p) { $p = '-' }; $l = ''; if ($a.locked) { $l = ', LOCKED' }; '  {0}, role {1}, created by {2}{3}' -f $a.loginName, $a.roleName, $p, $l; '  rights: ' + (($a.administratorRights.PSObject.Properties | Where-Object { $_.Value -eq $true } | ForEach-Object { $_.Name }) -join ', '); $t = $a.passwordCredentials.lastLoginTime; if (-not $t) { $t = 'never' }; '  last login {0}, API keys {1}' -f $t, @($a.apiKeys).Count"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
