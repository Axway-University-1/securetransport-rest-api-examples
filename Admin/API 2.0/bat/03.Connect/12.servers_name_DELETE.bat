@echo off
REM ==============================================================================
REM Script Name: 12.servers_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a server using the `/servers/{name}` endpoint.
REM It demonstrates:
REM - A direct DELETE request for a server by name
REM - A conditional DELETE request after checking server existence
REM
REM Usage:
REM 12.servers_name_DELETE.bat
REM
REM Notes:
REM - Ensure that `set_variables.bat` is correctly configured and called.
REM - The server name must be valid and exist in the system.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET NAME=SSH_TEST_SERVER_1
echo Deleting server '%NAME%'...
curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" ^
-H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"
echo Done

SET NAME=SSH_TEST_SERVER_2
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" ^
-H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C

IF "%RESPONSE_CODE%"=="200" (
    echo Server exists. Deleting server '%NAME%'...
    curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" ^
    -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"
    echo.
    echo Done
) ELSE (
    echo Server does not exist.
)
