@echo off
REM ==============================================================================
REM Script Name: 09.routes_POST_composite.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the five composite routes that tie it together, using the `/routes`
REM endpoint, one per scenario that has an outbound leg (2.2 to 2.6). Each is
REM built from the one template, attached to its own subscription, and has one
REM ExecuteRoute step that runs its own simple route.
REM
REM Usage:
REM 09.routes_POST_composite.bat
REM
REM Risk: write
REM
REM Notes:
REM - Needs the ids saved by 06.routes_POST_template.bat, 07.routes_POST_simple.bat
REM   and 08.subscriptions_POST.bat.
REM - Uses PowerShell to build the JSON bodies.
REM - The ids are saved as BT_ID_COMPOSITE_2 to BT_ID_COMPOSITE_6.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF NOT DEFINED BT_ID_TEMPLATE (
    echo BT_ID_TEMPLATE is not saved. Run 06.routes_POST_template.bat first.
    EXIT /B 1
)

CALL :create_composite_route 2
CALL :create_composite_route 3
CALL :create_composite_route 4
CALL :create_composite_route 5
CALL :create_composite_route 6
EXIT /B 0

:create_composite_route
SET SCENARIO_N=%1
SET ROUTE_NAME=%BT_COMPOSITE_ROUTE_PREFIX%%SCENARIO_N%
CALL SET SUB_ID=%%BT_ID_SUBSCRIPTION_%SCENARIO_N%%%
CALL SET SIMPLE_ID=%%BT_ID_SIMPLE_%SCENARIO_N%%%
IF NOT DEFINED SUB_ID (
    echo BT_ID_SUBSCRIPTION_%SCENARIO_N% or BT_ID_SIMPLE_%SCENARIO_N% is not saved. Run 07.routes_POST_simple.bat and 08.subscriptions_POST.bat first.
    EXIT /B 1
)
IF NOT DEFINED SIMPLE_ID (
    echo BT_ID_SUBSCRIPTION_%SCENARIO_N% or BT_ID_SIMPLE_%SCENARIO_N% is not saved. Run 07.routes_POST_simple.bat and 08.subscriptions_POST.bat first.
    EXIT /B 1
)

SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='COMPOSITE'; account=$env:BT_TEST_ACCOUNT; name=$env:ROUTE_NAME; conditionType='MATCH_ALL'; routeTemplate=$env:BT_ID_TEMPLATE; subscriptions=@($env:SUB_ID); steps=@(@{ type='ExecuteRoute'; status='ENABLED'; autostart=$false; executeRoute=$env:SIMPLE_ID }) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the composite route %ROUTE_NAME%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" BT_ID_COMPOSITE_%SCENARIO_N%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
