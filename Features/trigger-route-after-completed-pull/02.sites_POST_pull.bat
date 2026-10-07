@echo off
REM ==============================================================================
REM Script Name: 02.sites_POST_pull.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the transfer site the account pulls from, using the `/sites` endpoint.
REM It is an SSH site that points at this server's own SSH listener, and its
REM download folder is where the files to be pulled are waiting.
REM
REM Usage:
REM 02.sites_POST_pull.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - doAsIn renames each file as it is received, to ${stenv.target}_PULLED, so the
REM   inbound rows in File Tracking can be told from the outbound ones.
REM - The SSH port is AR_SSH_PORT, 8022 by default. It is not the REST API port.
REM - If the pull later fails to log in, check first whether this server allows an
REM   account to open an SSH session to itself.
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

powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name=$env:AR_PULL_SITE; host=$env:AR_SSH_HOST; port=$env:AR_SSH_PORT; userName=$env:AR_TEST_ACCOUNT; usePassword=$true; password=$env:AR_ACCOUNT_PASSWORD; account=$env:AR_TEST_ACCOUNT; transferType='partner'; downloadFolder=$env:AR_PULL_FROM_FOLDER; downloadPatternType='glob'; downloadPattern='*'; postTransmissionActions=@{ doAsIn=$env:AR_PULL_RENAME } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the pull site %AR_PULL_SITE%...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" -d "@%BODY_FILE%"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
