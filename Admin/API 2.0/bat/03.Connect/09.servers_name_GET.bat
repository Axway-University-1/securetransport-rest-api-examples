@echo off
REM ==============================================================================
REM Script Name: 09.servers_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script retrieves information about a specific server using the
REM /servers/{name} endpoint. It demonstrates:
REM - A full GET request for a server by name
REM - A filtered GET request using the fields parameter (requires protocol)
REM
REM Usage:
REM call 09_servers_name_GET.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - The fields parameter must be used in combination with protocol.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

set SERVER_NAME=SSH_TEST_SERVER_1

REM Full server details
echo.
echo Getting %SERVER_NAME%...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%SERVER_NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"

REM Filtered fields (requires protocol)
echo.
echo Getting %SERVER_NAME% with applied fields...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%SERVER_NAME%?fields=isActive,port&protocol=ssh" -H "accept: application/json" -H "%REFERER_HEADER%"
