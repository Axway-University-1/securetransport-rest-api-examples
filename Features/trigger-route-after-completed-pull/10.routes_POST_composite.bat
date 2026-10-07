@echo off
REM ==============================================================================
REM Script Name: 10.routes_POST_composite.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the composite route that ties it together, using the `/routes` endpoint.
REM It is built from the template, is attached to the subscription, and has one
REM ExecuteRoute step that runs the simple route.
REM
REM Usage:
REM 10.routes_POST_composite.bat
REM
REM Risk: write
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - Needs the ids saved by steps 6, 7 and 9.
REM - The id is saved as AR_ID_COMPOSITE for the cleanup.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF NOT DEFINED AR_ID_TEMPLATE (
    echo AR_ID_TEMPLATE is not saved. Run step 6 first.
    EXIT /B 1
)

IF NOT DEFINED AR_ID_SIMPLE (
    echo AR_ID_SIMPLE is not saved. Run step 7 first.
    EXIT /B 1
)

IF NOT DEFINED AR_ID_SUBSCRIPTION (
    echo AR_ID_SUBSCRIPTION is not saved. Run step 9 first.
    EXIT /B 1
)

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='COMPOSITE'; account=$env:AR_TEST_ACCOUNT; name=$env:AR_COMPOSITE_ROUTE; conditionType='MATCH_ALL'; routeTemplate=$env:AR_ID_TEMPLATE; subscriptions=@($env:AR_ID_SUBSCRIPTION); steps=@(@{ type='ExecuteRoute'; status='ENABLED'; autostart=$false; executeRoute=$env:AR_ID_SIMPLE }) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the composite route %AR_COMPOSITE_ROUTE%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" AR_ID_COMPOSITE
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
