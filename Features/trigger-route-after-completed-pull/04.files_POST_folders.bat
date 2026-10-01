@echo off
REM ==============================================================================
REM Script Name: 04.files_POST_folders.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the folders the example needs in the account's home, using the End User
REM API `POST /files/{name}` endpoint. It logs in to the End User API as the test account
REM itself, on the End User port, and logs out again at the end.
REM
REM Usage:
REM 04.files_POST_folders.bat
REM
REM Notes:
REM - Run 01.accounts_POST first.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Which folders is set by AR_CREATE_FOLDERS: outbound-drop, where the pull
REM   finds its files, and delivered, where the push puts them.
REM - Uses PowerShell to build the JSON body.
REM - The port is AR_ENDUSER_PORT, 8443 by default. It is not the Admin port.
REM - The folder's name goes in the URL, and the body says it is a directory. POST
REM   /files with the name in the body is refused with a 409, whatever the body.
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

CALL "%~dp0enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

FOR %%F IN (%AR_CREATE_FOLDERS%) DO CALL :create_folder %%F

CALL "%~dp0enduser.bat" logout
EXIT /B 0

:create_folder
SET FOLDER_NAME=%1
SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
REM The folder's name is in the URL. The body describes it as a directory.
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the folder %FOLDER_NAME%...
CALL "%~dp0enduser.bat" call POST "files/%FOLDER_NAME%" "application/json" "%BODY_FILE%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
