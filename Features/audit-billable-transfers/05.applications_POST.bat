@echo off
REM ==============================================================================
REM Script Name: 05.applications_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the Advanced Routing application every subscription here belongs to,
REM using the `/applications` endpoint. A subscription has to name an application
REM that exists.
REM
REM Usage:
REM 05.applications_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='AdvancedRouting'; name=$env:BT_APPLICATION; notes='Application for ' + $env:BT_APPLICATION } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the application %BT_APPLICATION%...
CALL "%~dp0..\lib\post_admin.bat" applications "%BODY_FILE%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
