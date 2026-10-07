@echo off
REM ==============================================================================
REM Script Name: 05.files_upload_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Puts the sample files in the pull folder, using the End User API `/fileOperations`
REM endpoint. It logs in to the End User API as the test account itself, on the End
REM User port, and logs out again at the end.
REM
REM Each file is two calls: the first declares the upload and returns an operation
REM id, the second sends the content to that id.
REM
REM Usage:
REM 05.files_upload_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Run 04.files_POST_folders first, so the folder exists.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the JSON body and to read the id.
REM - The port is AR_ENDUSER_PORT, 8443 by default. It is not the Admin port.
REM - The content is sent with PUT, not POST: POST is refused with a 415 for every
REM   content type except multipart, and multipart names the file after the local
REM   one instead of the path declared in the first call.
REM - The operation is asynchronous: the status in the first response is the
REM   operation's, not the upload's.
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

SET UPLOAD_FAILED=
FOR /L %%I IN (1,1,%AR_SAMPLE_FILES%) DO CALL :upload_file %%I

CALL "%~dp0..\lib\enduser.bat" logout
IF DEFINED UPLOAD_FAILED EXIT /B 1
EXIT /B 0

:upload_file
IF DEFINED UPLOAD_FAILED EXIT /B 1
SET FILE_PATH=%AR_UPLOAD_FOLDER%/%AR_SAMPLE_PREFIX%%1.txt
SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
SET CONTENT_FILE=%TEMP%\ar_content_%RANDOM%.txt
SET OPERATION_ID=

REM 1. Declare the upload, and read the operation id from the response
powershell -NoProfile -Command "@{ operation='Upload'; filePath=$env:FILE_PATH; customAttributes=@{ transferMode='ASCII' } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Declaring the upload of %FILE_PATH%...
CALL "%~dp0..\lib\enduser.bat" call POST fileOperations "application/json" "%BODY_FILE%"

FOR /F "delims=" %%O IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).id } catch { }"') DO SET OPERATION_ID=%%O

IF NOT DEFINED OPERATION_ID (
    echo No operation id came back ^(HTTP %EU_CODE%^), so nothing was uploaded. The response was:
    TYPE "%EU_BODY_FILE%"
    SET UPLOAD_FAILED=1
    GOTO :upload_done
)

REM 2. Send the content to that operation
echo Sending the content to operation %OPERATION_ID%...
> "%CONTENT_FILE%" echo Sample file %1 for the pull test.
CALL "%~dp0..\lib\enduser.bat" call PUT "fileOperations/%OPERATION_ID%" "application/octet-stream" "%CONTENT_FILE%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.

:upload_done
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%CONTENT_FILE%" DEL "%CONTENT_FILE%"
EXIT /B 0
