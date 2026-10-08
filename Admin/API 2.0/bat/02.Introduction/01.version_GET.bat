@echo off
REM ==============================================================================
REM Script Name: 01.version_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs a basic authentication request to retrieve the current
REM product version from the API. It uses username and password credentials and
REM sends a GET request to the `/version` endpoint.
REM
REM Usage:
REM 01.version_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script uses basic authentication and will be updated to token-based
REM   authentication in future iterations.
REM - 02.version_GET.bat makes the very same call and then picks fields out of the answer with findstr.
REM - Confirmed directly: the answer is 200 with serverType, version, build, os, updateLevel and more. Refused credentials
REM   answer 401 with the plain text "Authentication required.": the script prints the status and that text, and exits 1.
REM - Exit codes: 0 when the answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

REM Load environment variables
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\version_response_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Perform GET request to retrieve product version
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/version" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
EXIT /B 0

REM End of script

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
