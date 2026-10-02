@echo off
REM ==============================================================================
REM Script Name: 01.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the test account that owns every site, subscription and route these
REM examples use, using the `/accounts` endpoint. It is a user account with its
REM own password, so the sites can log in to this server's SSH listener as it, and
REM the account can log in to the End User API to upload the sample files.
REM
REM Usage:
REM 01.accounts_POST.bat
REM
REM Notes:
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - transfersWebServiceAllowed is on. Without it the account cannot log in to the
REM   End User API, and that login fails with a 401.
REM - The account is created with a home folder of BT_HOME_FOLDER. 99.cleanup_DELETE
REM   removes the account again.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ name=$env:BT_TEST_ACCOUNT; type='user'; homeFolder=$env:BT_HOME_FOLDER; uid='1001'; gid='1001'; transfersWebServiceAllowed=$true; user=@{ name=$env:BT_TEST_ACCOUNT; passwordCredentials=@{ password=$env:BT_ACCOUNT_PASSWORD } } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the account %BT_TEST_ACCOUNT%...
CALL "%~dp0..\lib\post_admin.bat" accounts "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
