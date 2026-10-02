@echo off
REM ==============================================================================
REM Script Name: 04.files_POST_folders.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the folders these examples need in the account's home, using the End
REM User API `POST /files/{name}` endpoint: the shared drop folder, the two
REM delivered folders, the subscription folder, and six subfolders inside it, one
REM per scenario (subscription/s1 to subscription/s6).
REM
REM Usage:
REM 04.files_POST_folders.bat
REM
REM Notes:
REM - Run 01.accounts_POST.bat first.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body.
REM - The folder's name goes in the URL, and the body says it is a directory. POST
REM   /files with the name in the body is refused with a 409, whatever the body
REM   (confirmed on Features/trigger-route-after-completed-pull).
REM - UNVERIFIED: the subscription/sN subfolders are created with a second POST,
REM   after the subscription folder itself exists, on the assumption that creating
REM   a nested folder needs its parent to exist first, like a plain mkdir.
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

CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

REM Top level first: outbound-drop, delivered-1, delivered-2, subscription
SET DROP_NAME=%BT_DROP_FOLDER:/=%
SET DELIVERED1_NAME=%BT_DELIVERED_1_FOLDER:/=%
SET DELIVERED2_NAME=%BT_DELIVERED_2_FOLDER:/=%
SET SUBSCRIPTION_NAME=%BT_SUBSCRIPTION_FOLDER:/=%
CALL :create_folder %DROP_NAME%
CALL :create_folder %DELIVERED1_NAME%
CALL :create_folder %DELIVERED2_NAME%
CALL :create_folder %SUBSCRIPTION_NAME%

REM Then one subfolder of subscription per scenario
FOR %%N IN (1,2,3,4,5,6) DO CALL :create_folder %SUBSCRIPTION_NAME%/s%%N

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
