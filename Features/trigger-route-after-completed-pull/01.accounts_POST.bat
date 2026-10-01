@echo off
REM ==============================================================================
REM Script Name: 01.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the test account that owns the pull site, the subscription and the push
REM site, using the `/accounts` endpoint. It is a user account with its own
REM password, so the two sites can log in to this server's SSH listener as it.
REM
REM Usage:
REM 01.accounts_POST.bat
REM
REM Notes:
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - A password containing % or ! may not survive a batch file. Avoid them.
REM - transfersWebServiceAllowed is on. Without it the account cannot log in to the
REM   End User API, which steps 4 and 5 use, and the login fails with a 401.
REM - The account is created with a home folder of AR_HOME_FOLDER. Create the
REM   subfolders outbound-drop and delivered in it, and put some files in
REM   outbound-drop, before running the pull.
REM - 99.cleanup_DELETE.bat removes the account again.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF "%AR_ACCOUNT_PASSWORD%"=="" (
    echo AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

SET REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json

powershell -NoProfile -Command "@{ name=$env:AR_TEST_ACCOUNT; type='user'; homeFolder=$env:AR_HOME_FOLDER; uid='1001'; gid='1001'; transfersWebServiceAllowed=$true; user=@{ name=$env:AR_TEST_ACCOUNT; passwordCredentials=@{ password=$env:AR_ACCOUNT_PASSWORD } } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the account %AR_TEST_ACCOUNT%...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" -d "@%BODY_FILE%"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
