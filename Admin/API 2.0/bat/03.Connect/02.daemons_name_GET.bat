@echo off
REM ==============================================================================
REM Script Name: 02.daemons_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script queries the SSH daemon from the `/daemons/{name}` endpoint,
REM extracts the banner from the response, checks if it's defined, and simulates
REM a fake banner check.
REM
REM Usage:
REM 02.daemons_name_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The script uses basic authentication and filters JSON output using findstr and cut.
REM - Confirmed directly: /daemons/{name} answers only for ssh; any other name is 400 "Invalid value for parameter name,
REM   expected (ssh)". The answer holds maxConnections, preferBouncyCastleProvider and banner (an empty text when none is set).
REM - Every call is checked: a status other than 200 prints the status and the answer and ends the script with exit 1.
REM - Exit codes: 0 when both answers are 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\daemon_response_%RANDOM%.json

set NAME=ssh
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Query the SSH daemon
SET "URL=%MAIN_URL%/%NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Read it again, to pick the banner out of the response
SET "URL=%MAIN_URL%/%NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1

REM Extract banner using PowerShell
set BANNER=
for /f "delims=" %%i in ('powershell -NoProfile -Command "$json = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $json.banner"') do (
    set BANNER=%%i
)

REM Check if banner is defined
if "%BANNER%"=="" (
    echo There is no banner defined.
) else (
    echo There is a banner defined: '%BANNER%'.
)

REM Simulate a fake banner
set FAKE_JSON={"banner": "This is a SecureTransport REST API test banner."}
for /f "delims=" %%i in ('powershell -NoProfile -Command "$json = $env:FAKE_JSON | ConvertFrom-Json; $json.banner"') do (
    set BANNER=%%i
)

REM Check if fake banner is defined
if "%BANNER%"=="" (
    echo There is no banner defined.
) else (
    echo There is a banner defined: '%BANNER%'.
)
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
