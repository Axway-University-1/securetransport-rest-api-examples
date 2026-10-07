@echo off
REM ==============================================================================
REM Script Name: 06.routes_POST_template.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the route package template, using the `/routes` endpoint. A composite
REM route (step 10) is built from a template, so it has to exist first.
REM
REM Usage:
REM 06.routes_POST_template.bat
REM
REM Risk: write
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - The id is saved as AR_ID_TEMPLATE for the later steps.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ name=$env:AR_TEMPLATE_ROUTE; description='Package template for ' + $env:AR_TEMPLATE_ROUTE; type='TEMPLATE'; conditionType='MATCH_ALL' } | ConvertTo-Json -Compress" > "%BODY_FILE%"

echo Creating the route template %AR_TEMPLATE_ROUTE%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" AR_ID_TEMPLATE
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
