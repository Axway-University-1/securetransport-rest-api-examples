@echo off
REM ==============================================================================
REM Script Name: 12.files_PUT_triggerfile.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Works around a known defect: when the pull renames the files it receives (the
REM _PULLED suffix), the trigger file written to the file system still lists their
REM ORIGINAL names, so the route cannot find them. This finds the newest trigger
REM file in the subscription folder and uploads it again with the current names,
REM using the End User API `/fileOperations` endpoint:
REM
REM   pull_test_1.txt_PULLED
REM   pull_test_2.txt_PULLED
REM   pull_test_3.txt_PULLED
REM
REM The server refuses to write over the existing trigger file (HTTP 403), because
REM the system created it, not the account. So the old file is deleted first and the
REM new one is uploaded under the same name. Uploading into the subscription folder
REM is a new arrival, so the subscription triggers again, this time on a correct
REM list.
REM
REM Usage:
REM 12.files_PUT_triggerfile.bat
REM
REM Notes:
REM - Run it after 11.transfers_pull_POST.bat. It waits up to AR_WAIT_SECONDS for the
REM   trigger file to appear, because the pull is asynchronous. The first route
REM   execution, on the wrong names, is expected to fail. This is the workaround for
REM   that, and it can be removed when the defect is fixed.
REM - The names come from the settings: AR_SAMPLE_PREFIX, AR_SAMPLE_FILES and
REM   AR_PULLED_SUFFIX.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to read the listing and to build the JSON body.
REM - If the old trigger file cannot be deleted either, the new one is uploaded as
REM   <name>_fixed.trigger. It still ends in .trigger, so the trigger condition
REM   matches it.
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

REM The names the files have now
SET CONTENT_FILE=%TEMP%\ar_content_%RANDOM%.txt
TYPE NUL > "%CONTENT_FILE%"
FOR /L %%I IN (1,1,%AR_SAMPLE_FILES%) DO >> "%CONTENT_FILE%" echo %AR_SAMPLE_PREFIX%%%I.txt%AR_PULLED_SUFFIX%

CALL "%~dp0enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

REM The newest trigger file in the subscription folder. The pull is asynchronous, so
REM give the trigger file time to appear.
SET WAITED=0
:find_trigger
CALL "%~dp0enduser.bat" call GET "files%AR_SUBSCRIPTION_FOLDER%" ""
SET TRIGGER=
FOR /F "delims=" %%T IN ('powershell -NoProfile -Command "try { $f = (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile -and $_.fileName -like '*.trigger' } | Sort-Object lastModifiedTime | Select-Object -Last 1; if ($f) { $f.fileName } } catch { }"') DO SET TRIGGER=%%T
IF DEFINED TRIGGER GOTO :found_trigger
IF %WAITED% GEQ %AR_WAIT_SECONDS% GOTO :found_trigger
echo No trigger file in %AR_SUBSCRIPTION_FOLDER% yet. Waiting...
ping -n 4 127.0.0.1 >NUL
SET /A WAITED=%WAITED%+3
GOTO :find_trigger
:found_trigger

IF NOT DEFINED TRIGGER (
    echo No trigger file in %AR_SUBSCRIPTION_FOLDER%. Has the pull in step 11 finished?
    CALL "%~dp0enduser.bat" logout
    IF EXIST "%CONTENT_FILE%" DEL "%CONTENT_FILE%"
    EXIT /B 1
)

REM The system owns the trigger file, so it cannot be written over. Delete it first.
echo Deleting the old trigger file %AR_SUBSCRIPTION_FOLDER%/%TRIGGER%...
SET TARGET=%TRIGGER%
CALL "%~dp0enduser.bat" call DELETE "files%AR_SUBSCRIPTION_FOLDER%/%TRIGGER%" ""
IF ERRORLEVEL 1 (
    SET TARGET=%TRIGGER:.trigger=_fixed.trigger%
    echo It could not be deleted ^(HTTP %EU_CODE%^), so the new one is uploaded as %TRIGGER:.trigger=_fixed.trigger% instead.
) ELSE (
    echo HTTP %EU_CODE%
)

echo Uploading %AR_SUBSCRIPTION_FOLDER%/%TARGET% with:
TYPE "%CONTENT_FILE%"

REM 1. Declare the upload, and read the operation id from the response
SET FILE_PATH=%AR_SUBSCRIPTION_FOLDER%/%TARGET%
SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ operation='Upload'; filePath=$env:FILE_PATH; customAttributes=@{ transferMode='ASCII' } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
CALL "%~dp0enduser.bat" call POST fileOperations "application/json" "%BODY_FILE%"
SET OPERATION_ID=
FOR /F "delims=" %%O IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).id } catch { }"') DO SET OPERATION_ID=%%O

IF NOT DEFINED OPERATION_ID (
    echo No operation id came back ^(HTTP %EU_CODE%^), so nothing was changed. The response was:
    TYPE "%EU_BODY_FILE%"
    CALL "%~dp0enduser.bat" logout
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    IF EXIST "%CONTENT_FILE%" DEL "%CONTENT_FILE%"
    EXIT /B 1
)

REM 2. Send the new content to that operation
CALL "%~dp0enduser.bat" call PUT "fileOperations/%OPERATION_ID%" "application/octet-stream" "%CONTENT_FILE%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.

CALL "%~dp0enduser.bat" logout
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%CONTENT_FILE%" DEL "%CONTENT_FILE%"
EXIT /B 0
