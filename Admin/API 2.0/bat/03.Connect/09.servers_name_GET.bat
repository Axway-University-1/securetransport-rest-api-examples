@echo off
REM ==============================================================================
REM Script Name: 09.servers_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves information about a specific server using the `/servers/{name}` endpoint.
REM It demonstrates:
REM - A full GET request for a server by name
REM - A filtered GET request using the `fields` parameter (requires `protocol`)
REM
REM Usage:
REM 09.servers_name_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The `fields` parameter must be used in combination with `protocol`.
REM - Confirmed directly: a server that does not exist is a 404 with an HTML page ("HTTP Status 404 - Not Found"), not JSON;
REM   08.servers_name_HEAD.bat gets a bodiless 400 for the same name. The script prints the status and that page and exits 1.
REM - Exit codes: 0 when both answers are 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\server_response_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers

set SERVER_NAME=SSH_TEST_SERVER_1

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Full server details
echo.
echo Getting %SERVER_NAME%...
SET "URL=%MAIN_URL%/%SERVER_NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Filtered fields (requires protocol)
echo.
echo Getting %SERVER_NAME% with applied fields...
SET "URL=%MAIN_URL%/%SERVER_NAME%?fields=isActive,port&protocol=ssh"
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
