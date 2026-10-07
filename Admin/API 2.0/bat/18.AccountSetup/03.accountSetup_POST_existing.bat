@echo off
REM ==============================================================================
REM Script Name: 03.accountSetup_POST_existing.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a transfer site to an account that already exists, using
REM the `/accountSetup` endpoint. The account in the body is skipped, not
REM refused, so the same call works for a new account and an existing one.
REM
REM Usage:
REM 03.accountSetup_POST_existing.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Run 01.accountSetup_POST.bat first. This adds example_setup_site2 to
REM   example_setup. ACCOUNT_PASSWORD is read from the environment, as there.
REM - Confirmed directly: it answers 200, with "Account with name example_setup
REM   skipped because it already exists." and "Site with name example_setup_site2
REM   created.", each with its URL.
REM - 04.accounts_name_DELETE.bat removes the account and both sites.
REM - PowerShell is used to build the body and read the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=example_setup
IF "%ACCOUNT_PASSWORD%"=="" SET ACCOUNT_PASSWORD=change_me
SET BODY_FILE=%TEMP%\setup_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\setup_response_%RANDOM%.json

REM The account as it is, and the one new site
powershell -NoProfile -Command "@{ accountSetup = @{ account = @{ name=$env:ACCOUNT; type='user'; uid='41733'; gid='41733'; homeFolder=('/home/' + $env:ACCOUNT); user=@{ name=$env:ACCOUNT; passwordCredentials=@{ password=$env:ACCOUNT_PASSWORD } } }; sites = @(@{ type='ssh'; protocol='ssh'; name=($env:ACCOUNT + '_site2'); account=$env:ACCOUNT; host=$env:ST_SERVER; port='8022'; userName=$env:ACCOUNT; usePassword=$true; password=$env:ACCOUNT_PASSWORD; transferType='partner'; downloadFolder='/in'; downloadPattern='*' }) } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Adding a site to the existing account %ACCOUNT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accountSetup" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C

IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    GOTO :failed
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($m in $r.messages) { '  ' + $m.message }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:failed
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
