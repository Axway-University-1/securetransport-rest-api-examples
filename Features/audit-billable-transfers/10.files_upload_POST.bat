@echo off
REM ==============================================================================
REM Script Name: 10.files_upload_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates and uploads every sample file these scenarios pull, using the End User
REM API `/fileOperations` endpoint, into the shared drop folder (BT_DROP_FOLDER).
REM The two archives (for scenarios 2.5 and 2.6) are built locally with
REM PowerShell's Compress-Archive first, then uploaded as ordinary binary content.
REM
REM Usage:
REM 10.files_upload_POST.bat
REM
REM Notes:
REM - Run 01.accounts_POST.bat and 04.files_POST_folders.bat first.
REM - Scenarios 2.1 and 2.2 upload BT_INBOUND_ONLY_COUNT and BT_IN_AND_OUT_COUNT
REM   files, numbered when there is more than one. See settings.bat.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to build the archives and the JSON bodies.
REM - The content call uses PUT, not POST: POST is refused with a 415 (confirmed
REM   on Features/trigger-route-after-completed-pull).
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

SET WORK=%TEMP%\bt_upload_%RANDOM%
MKDIR "%WORK%"

CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 (
    RMDIR /S /Q "%WORK%"
    EXIT /B 1
)

CALL :upload_scenario_files "%BT_FILE_ONLY_INBOUND%" %BT_INBOUND_ONLY_COUNT% "Scenario 2.1: only inbound, no outbound at all."
CALL :upload_scenario_files "%BT_FILE_ONE_OUTBOUND%" %BT_IN_AND_OUT_COUNT% "Scenario 2.2: inbound, then pushed out once."
CALL :upload_text_file "%BT_FILE_TWO_OUTBOUNDS%" "Scenario 2.3: inbound, then pushed out twice."
CALL :upload_text_file "%BT_FILE_COMPRESS_1%" "Scenario 2.4, file 1 of 2, to be compressed together."
CALL :upload_text_file "%BT_FILE_COMPRESS_2%" "Scenario 2.4, file 2 of 2, to be compressed together."

CALL :build_archive "%BT_FILE_ARCHIVE_NAME%" "%BT_FILE_DECOMPRESS_1%" "Scenario 2.5, file 1 of 2, inside the archive." "%BT_FILE_DECOMPRESS_2%" "Scenario 2.5, file 2 of 2, inside the archive."
CALL :build_archive "%BT_FILE_ARCHIVE2P_NAME%" "%BT_FILE_DECOMPRESS2P_1%" "Scenario 2.6, file 1 of 2, pushed on to two partners." "%BT_FILE_DECOMPRESS2P_2%" "Scenario 2.6, file 2 of 2, pushed on to two partners."

CALL "%~dp0..\lib\enduser.bat" logout
RMDIR /S /Q "%WORK%"
EXIT /B 0

REM upload_scenario_files NAME COUNT TEXT
REM   One file under NAME when COUNT is 1, otherwise COUNT numbered copies:
REM   only_inbound.txt, or only_inbound_1.txt to only_inbound_<COUNT>.txt
:upload_scenario_files
SET USF_NAME=%~1
SET USF_COUNT=%~2
SET USF_TEXT=%~3
IF "%USF_COUNT%"=="1" (
    CALL :upload_text_file "%USF_NAME%" "%USF_TEXT%"
    EXIT /B 0
)
FOR /L %%I IN (1,1,%USF_COUNT%) DO CALL :upload_text_file "%USF_NAME:.txt=%_%%I.txt" "%USF_TEXT% File %%I of %USF_COUNT%."
EXIT /B 0

:upload_text_file
SET UP_NAME=%~1
SET UP_TEXT=%~2
SET UP_LOCAL=%WORK%\%UP_NAME%
> "%UP_LOCAL%" echo %UP_TEXT%
CALL :upload_bytes "%BT_DROP_FOLDER%/%UP_NAME%" "%UP_LOCAL%"
EXIT /B 0

:build_archive
SET UP_ARCHIVE_NAME=%~1
SET UP_FILE_A=%~2
SET UP_TEXT_A=%~3
SET UP_FILE_B=%~4
SET UP_TEXT_B=%~5
SET UP_ARCHIVE_DIR=%WORK%\%UP_ARCHIVE_NAME:.zip=%
MKDIR "%UP_ARCHIVE_DIR%"
> "%UP_ARCHIVE_DIR%\%UP_FILE_A%" echo %UP_TEXT_A%
> "%UP_ARCHIVE_DIR%\%UP_FILE_B%" echo %UP_TEXT_B%
SET UP_ARCHIVE_PATH=%WORK%\%UP_ARCHIVE_NAME%
powershell -NoProfile -Command "Compress-Archive -Path (Join-Path $env:UP_ARCHIVE_DIR '*') -DestinationPath $env:UP_ARCHIVE_PATH -Force"
CALL :upload_bytes "%BT_DROP_FOLDER%/%UP_ARCHIVE_NAME%" "%UP_ARCHIVE_PATH%"
EXIT /B 0

:upload_bytes
SET UB_PATH=%~1
SET UB_LOCAL=%~2
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ operation='Upload'; filePath=$env:UB_PATH; customAttributes=@{ transferMode='BINARY' } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Declaring the upload of %UB_PATH%...
CALL "%~dp0..\lib\enduser.bat" call POST fileOperations "application/json" "%BODY_FILE%"
SET OPERATION_ID=
FOR /F "delims=" %%O IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).id } catch { }"') DO SET OPERATION_ID=%%O

IF NOT DEFINED OPERATION_ID (
    echo No operation id came back ^(HTTP %EU_CODE%^), so nothing was uploaded. The response was:
    TYPE "%EU_BODY_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)

echo Sending the content to operation %OPERATION_ID%...
CALL "%~dp0..\lib\enduser.bat" call PUT "fileOperations/%OPERATION_ID%" "application/octet-stream" "%UB_LOCAL%"
echo HTTP %EU_CODE%
TYPE "%EU_BODY_FILE%"
echo.
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
