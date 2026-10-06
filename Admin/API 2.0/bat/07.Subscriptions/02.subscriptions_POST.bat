@echo off
REM ==============================================================================
REM Script Name: 02.subscriptions_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script subscribes an account's folder to an Advanced Routing application,
REM using the `/applications` and `/subscriptions` endpoints. It demonstrates:
REM - Creating the Advanced Routing application the subscription needs
REM - Creating the subscription, with the pull site as its PARTNER-IN transfer
REM   configuration, so that what the site pulls lands in the folder
REM - Reading the id of the new subscription from the Location header
REM
REM Usage:
REM 02.subscriptions_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account "john" and its site SSH_PULL must already exist. Run
REM   06.TransferSites\02.sites_POST_ssh.bat first.
REM - If the application already exists, its POST answers 409 and the
REM   subscription is created against the existing one.
REM - A route only runs on what arrives in the folder once a composite route is
REM   linked to the subscription. See
REM   09.CompositeRoutes\05.routes_POST_composite_subscription.bat.
REM - The bodies hold no spaces or special characters, so they are written inline.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=/inbox
SET PULL_SITE=SSH_PULL
SET HEADERS_FILE=%TEMP%\subscription_headers_%RANDOM%.txt

echo Creating the application '%APPLICATION%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" ^
  -d "{\"type\":\"AdvancedRouting\",\"name\":\"%APPLICATION%\",\"notes\":\"Created by 07.Subscriptions\"}"

echo Subscribing the folder '%FOLDER%' of '%ACCOUNT%' to '%APPLICATION%'...
curl -s -D "%HEADERS_FILE%" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "{\"type\":\"AdvancedRouting\",\"account\":\"%ACCOUNT%\",\"application\":\"%APPLICATION%\",\"folder\":\"%FOLDER%\",\"transferConfigurations\":[{\"tag\":\"PARTNER-IN\",\"outbound\":false,\"site\":\"%PULL_SITE%\"}]}"

SET HTTP_CODE=
SET LOCATION=
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%HEADERS_FILE%"') DO SET HTTP_CODE=%%C
FOR /F "tokens=2" %%L IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%L
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"

echo.
echo HTTP %HTTP_CODE%
IF DEFINED LOCATION FOR %%P IN ("%LOCATION%") DO echo New subscription ID: %%~nxP
