@echo off
REM ==============================================================================
REM Script Name: 02.accountSetup_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads an account with everything around it, in one call, using
REM the `/accountSetup/{name}` endpoint: the account, its certificates, transfer
REM sites, transfer profiles, routes and subscriptions.
REM
REM Usage:
REM 02.accountSetup_name_GET.bat [ACCOUNT]
REM
REM   ACCOUNT  the account to read (default example_setup, which
REM            01.accountSetup_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - With accept: application/json the certificates' properties come back; with
REM   multipart/mixed, the certificates themselves are exported.
REM - The answer is the same shape 01.accountSetup_POST.bat sends, so it can be
REM   kept as a template for setting up a similar account.
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=example_setup
SET RESPONSE_FILE=%TEMP%\setup_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accountSetup/%ACCOUNT%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C

IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the setup of %ACCOUNT% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo In short:
powershell -NoProfile -Command "$s = (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).accountSetup; '  account            {0} ({1}), home {2}' -f $s.account.name, $s.account.type, $s.account.homeFolder; '  certificates       {0}' -f (@($s.certificates.login) + @($s.certificates.partner) + @($s.certificates.private)).Count; '  sites              {0}' -f ((@($s.sites) | ForEach-Object { $_.name }) -join ', '); '  transfer profiles  {0}' -f ((@($s.transferProfiles) | ForEach-Object { $_.name }) -join ', '); '  routes             {0}' -f @($s.routes).Count; '  subscriptions      {0}' -f ((@($s.subscriptions) | ForEach-Object { $_.folder }) -join ', ')"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
