@echo off
REM ==============================================================================
REM Script Name: 02.configurations_PATCH_UsageReporting.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script configures automatic usage reporting to the Axway Platform by
REM patching the StatisticsSummaryReport Server Configuration Options.
REM
REM Usage:
REM 02.configurations_PATCH_UsageReporting.bat
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Fill in the client, secret and environment values below before running.
REM - Each option is patched by a CALL to the patch_option subroutine. Each CALL
REM   is its own statement, so no delayed expansion is needed.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET SCO=StatisticsSummaryReport
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations/options

REM
REM Those relate to the User and Environment you want to use from the Axway Platform.
REM You can find those in the Axway Platform UI, at https://platform.axway.com/
REM
SET CLIENT_ID=<PUT YOUR CLIENT ID HERE>
SET CLIENT_SECRET=<PUT YOUR CLIENT_SECRET HERE>
SET ENVIRONMENT_ID=<PUT YOUR ENVIRONMENT_ID HERE>
SET ENVIRONMENT_NAME=<PUT YOUR ENVIRONMENT_NAME HERE>

REM
REM In case you have an edge through which the connection must pass to reach the
REM platform, define it here.
REM
SET NETWORK_ZONE=<PUT YOUR NETWORK_ZONE HERE>

REM
REM Set the default values for the configuration options.
REM In newer product versions, those are set by default.
REM
SET PLATFORM_API=https://platform.axway.com/api/v1/usage/automatic
SET PLATFORM_AUTHENTICATION=https://login.axway.com/auth/realms/Broker/protocol/openid-connect/token
SET SCHEMA_ID=https://platform.axway.com/schemas/report.json

SET PATH_TO_REPORTS=C:\Temp\
SET DAYS_TO_INCLUDE=3

REM Update the configuration options
CALL :patch_option "%SCO%.ClientId"                      "%CLIENT_ID%"
CALL :patch_option "%SCO%.ClientSecret"                  "%CLIENT_SECRET%"
CALL :patch_option "%SCO%.EnvironmentId"                 "%ENVIRONMENT_ID%"
CALL :patch_option "%SCO%.EnvironmentName"               "%ENVIRONMENT_NAME%"
CALL :patch_option "%SCO%.FilePath"                      "%PATH_TO_REPORTS%"
CALL :patch_option "%SCO%.NetworkZone"                   "%NETWORK_ZONE%"
CALL :patch_option "%SCO%.Platform.API"                  "%PLATFORM_API%"
CALL :patch_option "%SCO%.Platform.Authentication"       "%PLATFORM_AUTHENTICATION%"
CALL :patch_option "%SCO%.SchemaId"                      "%SCHEMA_ID%"
CALL :patch_option "%SCO%.AutomaticReport.DaysToInclude" "%DAYS_TO_INCLUDE%"

EXIT /B 0

REM ------------------------------------------------------------------------------
REM Patches the option named in %1 with the value in %2
REM ------------------------------------------------------------------------------
:patch_option
SET OPTION=%~1
SET VALUE=%~2

echo Updating %OPTION% to '%VALUE%'...
curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%OPTION%" ^
-H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{\"op\": \"replace\", \"path\": \"/values\", \"value\": [\"%VALUE%\"]}]"
EXIT /B
