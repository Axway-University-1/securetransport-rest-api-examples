@echo off
REM ==============================================================================
REM Script Name: 08.servers_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a specific server exists using the HTTP HEAD method.
REM It uses curl's `--head` option to retrieve only the response headers.
REM A 200 response code indicates the server exists; 400 or 404 means it does not (see Notes).
REM
REM Usage:
REM 08.servers_name_HEAD.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - HEAD requests are efficient for existence checks without retrieving full content.
REM - Confirmed directly: the lab answers a HEAD of a server that does not exist with 400 and no body (a HEAD never has one),
REM   not the 404 the reference leads one to expect; a GET of the same name (09.servers_name_GET.bat) is a 404 with an HTML page.
REM   So the script reads the code from the answer: 200 is "Server exists.", 400 or 404 is "Server does not exist." and any
REM   other code (401, 500) is "Could not check the server." - each with the status, and exit 1 for the last two.
REM - Exit codes: 0 when the server exists, 1 when it does not or the check could not be made.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

set NAME=SSH_TEST_SERVER_1

REM Perform HEAD request
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"

REM Check response code
SET RESPONSE_CODE=
FOR /F %%i IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%i
IF "%RESPONSE_CODE%"=="200" (
    echo Server exists.
    EXIT /B 0
)
IF "%RESPONSE_CODE%"=="400" GOTO missing
IF "%RESPONSE_CODE%"=="404" GOTO missing
echo Could not check the server. HTTP %RESPONSE_CODE%
EXIT /B 1

:missing
echo Server does not exist. HTTP %RESPONSE_CODE%
EXIT /B 1
