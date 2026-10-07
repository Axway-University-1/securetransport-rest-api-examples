@echo off
REM ==============================================================================
REM Script Name: 04.subscriptions_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes subscriptions using the `/subscriptions/{id}` endpoint,
REM and then the application they used. It demonstrates:
REM - Looking up the id of a subscription by account and folder
REM - Deleting the subscription by that id
REM - Deleting the application, once nothing subscribes to it
REM
REM Usage:
REM 04.subscriptions_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up what 02.subscriptions_POST.bat and
REM   03.subscriptions_POST_triggerfile.bat create for the account "john": the
REM   subscriptions on /inbox and /inbox-trigger, and the application
REM   AdvancedRoutingApplication. Only ever point it at what you created.
REM - Delete a composite route that is linked to a subscription first. See
REM   09.CompositeRoutes\07.routes_id_DELETE.bat.
REM - PowerShell is used to pick the subscription out of the response, in place
REM   of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET APPLICATION=AdvancedRoutingApplication
SET RESPONSE_FILE=%TEMP%\subscriptions_%RANDOM%.json

FOR %%F IN (/inbox /inbox-trigger) DO CALL :delete_subscription %%F

echo Deleting the application '%APPLICATION%'...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE ^
  "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%APPLICATION%" ^
  -H "accept: */*" -H "%REFERER_HEADER%"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:delete_subscription
SET FOLDER=%1
SET SUBSCRIPTION_ID=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions?account=%ACCOUNT%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { ((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.folder -eq $env:FOLDER -and $_.application -eq $env:APPLICATION } | Select-Object -First 1).id } catch { }"') DO SET SUBSCRIPTION_ID=%%I

IF "%SUBSCRIPTION_ID%"=="" (
    echo The account '%ACCOUNT%' has no subscription on '%FOLDER%'.
    EXIT /B 0
)

echo Deleting the subscription on '%FOLDER%' (%SUBSCRIPTION_ID%)...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE ^
  "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions/%SUBSCRIPTION_ID%" ^
  -H "accept: */*" -H "%REFERER_HEADER%"
EXIT /B 0
