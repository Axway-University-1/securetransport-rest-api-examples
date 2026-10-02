@echo off
REM ==============================================================================
REM Script Name: 08.applications_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the Advanced Routing application the subscription belongs to, using the
REM `/applications` endpoint. A subscription has to name an application that
REM exists, and there is no application called AdvRouting on a new server.
REM
REM Usage:
REM 08.applications_POST.bat
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - The application is called AR_APPLICATION in settings.bat.
REM - The id is saved as AR_ID_APPLICATION, and 99.cleanup_DELETE.bat deletes it.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='AdvancedRouting'; name=$env:AR_APPLICATION; notes='Application for ' + $env:AR_APPLICATION } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the application %AR_APPLICATION%...
CALL "%~dp0..\lib\post_admin.bat" applications "%BODY_FILE%" AR_ID_APPLICATION
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
