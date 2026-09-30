@echo off
REM ==============================================================================
REM Script Name: 08.servers_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script checks whether a specific server exists using the HTTP HEAD method.
REM It uses curl's --head option to retrieve only the response headers.
REM A 200 response code indicates the server exists; 404 means it does not.
REM
REM Usage:
REM call 08_servers_name_HEAD.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - HEAD requests are efficient for existence checks without retrieving full content.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

set NAME=SSH_TEST_SERVER_1

REM Perform HEAD request
curl -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"

REM Check response code
for /f %%i in ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') do (
    set RESPONSE_CODE=%%i
)

if "%RESPONSE_CODE%"=="200" (
    echo Server exists.
) else (
    echo Server does not exist.
)
