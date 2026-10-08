@echo off
REM ==============================================================================
REM Script Name: 05.myself_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs a POST request to the `/myself` endpoint, which is related
REM to user authentication. It initiates a session or validates credentials depending
REM on the API implementation.
REM
REM Usage:
REM 05.myself_POST.bat
REM
REM Risk: read
REM
REM Notes:
REM - For complete documentation, refer to folder 01.Authentication.
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer to a login is 200 {"message": "Logged in"}; 401 with the plain text "Authentication
REM   required." for refused credentials. The script prints the status and the answer when it is not 200, and exits 1.
REM - 01.Authentication/01.myself_POST.bat makes the same call.
REM - Exit codes: 0 when the login is accepted (200), 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
