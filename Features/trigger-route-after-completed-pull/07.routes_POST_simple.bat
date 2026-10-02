@echo off
REM ==============================================================================
REM Script Name: 07.routes_POST_simple.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the simple route that sends the pulled files to the push site, using
REM the `/routes` endpoint. It is a single Send To Partner step. There is no
REM Compress step: the files go on as they arrived.
REM
REM Usage:
REM 07.routes_POST_simple.bat
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - Run 03.sites_POST_push.bat first: the step names the push site.
REM - The site is written as <site>#!#CVD#!# in transferSiteExpression. CVD is part
REM   of the separator, not a name. Several sites are joined the same way:
REM   <site1>#!#CVD#!#<site2>#!#CVD#!#
REM - The id is saved as AR_ID_SIMPLE for the later steps.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='SIMPLE'; name=$env:AR_SIMPLE_ROUTE; conditionType='ALWAYS'; condition=$true; steps=@(@{ type='SendToPartner'; status='ENABLED'; autostart=$false; transferSiteExpressionType='LIST'; transferSiteExpression=($env:AR_PUSH_SITE + '#!#CVD#!#'); fileFilterExpressionType='GLOB'; fileFilterExpression='*'; actionOnStepFailure='FAIL' }) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the simple route %AR_SIMPLE_ROUTE%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" AR_ID_SIMPLE
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
