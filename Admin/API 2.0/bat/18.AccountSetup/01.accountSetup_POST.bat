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
REM [SET ACCOUNT_PASSWORD=the password of example_setup]
REM 01.accountSetup_POST.bat
REM
REM   ACCOUNT_PASSWORD  the password of example_setup and of its site's login (optional): when it is not set, one is generated
REM                     (12 random letters and digits after a fixed beginning) and printed once
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account is example_setup, with an SSH site named example_setup_site.
REM   ACCOUNT_PASSWORD is read from the environment (SET ACCOUNT_PASSWORD=the password first); when it is not set, a
REM   password is generated and printed, so the account is never created with a password anyone could guess.
REM - Every site, transfer profile and subscription in the body names its
REM   account too, even here: without it the call answers 400 "...account must
REM   not be null" (confirmed directly).
REM - Confirmed directly: the call is NOT all or nothing. A body that fails part
REM   of the way - for example a transfer profile on an account with no PeSIT
REM   site, "Account does not contain any PeSIT transfer sites." - answers 400,
REM   yet what came before it in the body has been created.
REM - The answer lists one message per object, with its URL.
REM - The site logs in over SSH on port 8022, or on ST_SSH_PORT when that is set (see set_variables.local.example.bat).
REM - Certificates are imported with a multipart/mixed body instead; see the API
REM   reference.
REM - 04.accounts_name_DELETE.bat removes the account, its sites and its profiles.
REM - PowerShell is used to build the body, in place of jq.
REM - The password is never in the file. A generated one is printed once, after the call, also when the call fails (part of the body
REM   may have been created: see above).
REM - Exit codes: 0 when the call answers 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=example_setup
SET "SSH_PORT=%ST_SSH_PORT%"
IF "%SSH_PORT%"=="" SET "SSH_PORT=8022"
SET BODY_FILE=%TEMP%\setup_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\setup_response_%RANDOM%.json

SET GENERATED=
IF NOT DEFINED ACCOUNT_PASSWORD (
    REM A generated password: written to a file by PowerShell and read back (a FOR /F command cannot hold single quotes)
    powershell -NoProfile -Command "[IO.File]::WriteAllText($env:RESPONSE_FILE, 'Ex1!' + (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })))"
    SET /P ACCOUNT_PASSWORD=<"%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    SET GENERATED=yes
)

powershell -NoProfile -Command "@{ accountSetup = @{ account = @{ name=$env:ACCOUNT; type='user'; uid='41733'; gid='41733'; homeFolder=('/home/' + $env:ACCOUNT); user=@{ name=$env:ACCOUNT; passwordCredentials=@{ password=$env:ACCOUNT_PASSWORD } } }; sites = @(@{ type='ssh'; protocol='ssh'; name=($env:ACCOUNT + '_site'); account=$env:ACCOUNT; host=$env:ST_SERVER; port=$env:SSH_PORT; userName=$env:ACCOUNT; usePassword=$true; password=$env:ACCOUNT_PASSWORD; transferType='partner'; uploadFolder='/out' }) } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Setting up the account %ACCOUNT% and its site, in one call...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accountSetup" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF "%GENERATED%"=="yes" echo The password of %ACCOUNT% is %ACCOUNT_PASSWORD% ^(generated: it is not shown again^).

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
