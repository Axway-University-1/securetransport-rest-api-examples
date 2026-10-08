@echo off
REM ==============================================================================
REM Script Name: 06.servers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script queries the `/servers` endpoint to retrieve server information.
REM It demonstrates how to:
REM - Get all servers
REM - Filter by specific fields
REM - Filter by protocol
REM - Use common filters like serverName, isActive, isFipsEnabled
REM - Use protocol-specific filters like isScpEnabled
REM
REM Usage:
REM 06.servers_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The script uses basic authentication and GET requests with query parameters.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials)
REM   prints the status and the answer and ends the script with exit 1.
REM - Exit codes: 0 when every answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\servers_response_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Get all servers
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Get only serverName and isActive fields
SET "URL=%MAIN_URL%?fields=id,serverName,isActive"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Filter by protocol: AS2
set PROTOCOL=as2
SET "URL=%MAIN_URL%?protocol=%PROTOCOL%&fields=id,serverName,isActive"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Filter by common fields
SET "URL=%MAIN_URL%?limit=1&offset=0&serverName=Ssh%%20Default&isActive=true&isFipsEnabled=false"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Filter by protocol-specific field
SET "URL=%MAIN_URL%?fields=isScpEnabled&protocol=ssh"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
