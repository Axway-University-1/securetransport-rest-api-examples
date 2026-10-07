@echo off
REM ==============================================================================
REM Script Name: 04.files_POST_folders.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the folders these examples need, using the End User API
REM `POST /files/{name}` endpoint, logged in as each account in turn:
REM   - the test account: the subscription folder, and six subfolders inside it,
REM     one per scenario (subscription/s1 to subscription/s6)
REM   - partner_to_pull_from: a folder named after the test account, and the drop
REM     folder inside it, where the sample files wait to be pulled
REM   - partner_to_push_to: a folder named after the test account, and the two
REM     delivered folders inside it, where the pushes arrive
REM
REM Usage:
REM 04.files_POST_folders.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - The folder's name goes in the URL, and the body says it is a directory. POST
REM   /files with the name in the body is refused with a 409, whatever the body
REM   (confirmed on Features/trigger-route-after-completed-pull).
REM - A nested folder is created after its parent, like a plain mkdir.
REM - The port is BT_ENDUSER_PORT, 8443 by default. It is not the Admin port.
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

REM The folder names without their leading /
SET SUBSCRIPTION_NAME=%BT_SUBSCRIPTION_FOLDER:~1%
SET RUN_NAME=%BT_RUN_FOLDER:~1%
SET DROP_NAME=%BT_DROP_FOLDER:~1%
SET DELIVERED1_NAME=%BT_DELIVERED_1_FOLDER:~1%
SET DELIVERED2_NAME=%BT_DELIVERED_2_FOLDER:~1%

REM The test account: the subscription folder, then one subfolder per scenario
SET EU_ACCOUNT=%BT_TEST_ACCOUNT%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_folder %SUBSCRIPTION_NAME%
FOR %%N IN (1,2,3,4,5,6) DO CALL :create_folder %SUBSCRIPTION_NAME%/s%%N
CALL "%~dp0..\lib\enduser.bat" logout

REM partner_to_pull_from: the test account's folder, then its drop folder
SET EU_ACCOUNT=%BT_PULL_PARTNER%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_folder %RUN_NAME%
CALL :create_folder %DROP_NAME%
CALL "%~dp0..\lib\enduser.bat" logout

REM partner_to_push_to: the test account's folder, then the two delivered folders
SET EU_ACCOUNT=%BT_PUSH_PARTNER%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1
CALL :create_folder %RUN_NAME%
CALL :create_folder %DELIVERED1_NAME%
CALL :create_folder %DELIVERED2_NAME%
CALL "%~dp0..\lib\enduser.bat" logout
EXIT /B 0

:create_folder
SET FOLDER_PATH=%1
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the folder %FOLDER_PATH%...
CALL "%~dp0..\lib\enduser.bat" call POST "files/%FOLDER_PATH%" "application/json" "%BODY_FILE%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
