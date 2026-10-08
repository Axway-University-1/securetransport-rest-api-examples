@echo off
REM ==============================================================================
REM Script Name: 01.daemons_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script queries the `/daemons` endpoint to retrieve system daemon statuses.
REM It demonstrates how to extract specific fields from the response, such as
REM `sshStatus`, using both full and filtered API calls.
REM
REM Usage:
REM 01.daemons_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The script uses basic authentication and filters JSON output using findstr.
REM - Confirmed directly: the answer is a flat object, {"ftpStatus": "Running", "httpStatus": "Running", "pesitStatus": ...,
REM   "sshStatus": ..., "as2Status": "Not running"}, and fields=sshStatus keeps that one key.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty answer.
REM - Exit codes: 0 when every answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\daemons_response_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Full response
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Store full response in a temporary file
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1

REM Extract sshStatus
echo.
echo Extracting sshStatus from full response...
findstr "sshStatus" "%RESPONSE_FILE%"

REM Filtered response using 'fields' parameter
echo.
echo Filtered response with only sshStatus field...
SET "URL=%MAIN_URL%?fields=sshStatus"
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
