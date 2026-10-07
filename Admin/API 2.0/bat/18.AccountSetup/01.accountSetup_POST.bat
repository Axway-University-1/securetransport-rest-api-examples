@echo off
REM ==============================================================================
REM Script Name: 01.accountSetup_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates an account and its transfer site in one call, using the
REM `/accountSetup` endpoint. One body can carry the account, its certificates,
REM sites, transfer profiles, routes and subscriptions.
REM
REM Usage:
REM 01.accountSetup_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account is example_setup, with an SSH site named example_setup_site.
REM   ACCOUNT_PASSWORD is read from the environment, so set it first:
REM     SET ACCOUNT_PASSWORD=the password
REM - Every site, transfer profile and subscription in the body names its
REM   account too, even here: without it the call answers 400 "...account must
REM   not be null" (confirmed directly).
REM - Confirmed directly: the call is NOT all or nothing. A body that fails part
REM   of the way - for example a transfer profile on an account with no PeSIT
REM   site, "Account does not contain any PeSIT transfer sites." - answers 400,
REM   yet what came before it in the body has been created.
REM - The answer lists one message per object, with its URL.
REM - Certificates are imported with a multipart/mixed body instead; see the API
REM   reference.
REM - 04.accounts_name_DELETE.bat removes the account, its sites and its profiles.
REM - PowerShell is used to build the body and read the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=example_setup
IF "%ACCOUNT_PASSWORD%"=="" SET ACCOUNT_PASSWORD=change_me
SET BODY_FILE=%TEMP%\setup_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\setup_response_%RANDOM%.json

powershell -NoProfile -Command "@{ accountSetup = @{ account = @{ name=$env:ACCOUNT; type='user'; uid='41733'; gid='41733'; homeFolder=('/home/' + $env:ACCOUNT); user=@{ name=$env:ACCOUNT; passwordCredentials=@{ password=$env:ACCOUNT_PASSWORD } } }; sites = @(@{ type='ssh'; protocol='ssh'; name=($env:ACCOUNT + '_site'); account=$env:ACCOUNT; host=$env:ST_SERVER; port='8022'; userName=$env:ACCOUNT; usePassword=$true; password=$env:ACCOUNT_PASSWORD; transferType='partner'; uploadFolder='/out' }) } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Setting up the account %ACCOUNT% and its site, in one call...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accountSetup" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C

IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%. Part of it may have been created all the same:
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
