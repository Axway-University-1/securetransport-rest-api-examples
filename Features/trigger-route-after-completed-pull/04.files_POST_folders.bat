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
REM Risk: write
REM
REM Notes:
REM - Run 01.accounts_POST first.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Which folders is set by AR_CREATE_FOLDERS: outbound-drop, where the pull
REM   finds its files, and delivered, where the push puts them.
REM - Uses PowerShell to build the JSON body.
REM - Stops at the first folder the server refuses (a 409 when it is already there), logs
REM   out, and exits 1.
REM - The port is AR_ENDUSER_PORT, 8443 by default. It is not the Admin port.
REM - Confirmed directly: an account's home folder stays on disk, with its owner, when the account is
REM   deleted. A new account with ANOTHER uid cannot create a folder directly in it: every such POST is 403
REM   "Error occurred while creating file: null" (folders below an existing one still work, which hides it).
REM   The script prints a hint; the fix is another account name, which gets a new home folder.
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

CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

SET FOLDER_FAILED=
FOR %%F IN (%AR_CREATE_FOLDERS%) DO CALL :create_folder %%F

CALL "%~dp0..\lib\enduser.bat" logout
IF DEFINED FOLDER_FAILED EXIT /B 1
EXIT /B 0

:create_folder
REM A refused folder stops the run: the later steps need it
IF DEFINED FOLDER_FAILED EXIT /B 1
SET FOLDER_NAME=%1
SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
REM The folder's name is in the URL. The body describes it as a directory.
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the folder %FOLDER_NAME%...
CALL "%~dp0..\lib\enduser.bat" call POST "files/%FOLDER_NAME%" "application/json" "%BODY_FILE%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.
IF "%EU_CODE%"=="403" FINDSTR /C:"Error occurred while creating file" "%EU_BODY_FILE%" >NUL && echo Hint: a 403 "Error occurred while creating file" for a folder directly in an account's home usually means the home folder is left over from an earlier run and belongs to another uid ^(it stays on disk when the account is deleted^). Use another account name ^(00.run_all.bat ANOTHER_NAME, or AR_TEST_ACCOUNT in settings.local.bat^), so that the account gets a new home folder.
IF NOT "%EU_CODE:~0,1%"=="2" SET FOLDER_FAILED=1
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
