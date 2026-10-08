@echo off
REM ==============================================================================
REM Script Name: 01.myself_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script logs in to the API with basic authentication, using POST on the
REM `/myself` endpoint, and prints the server's answer.
REM
REM Usage:
REM 01.myself_POST.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script does not use a cookie jar, so authentication is required for each call.
REM - POST /myself is the LOGIN call. Confirmed directly: it answers 200 with {"message": "Logged in"}, not the
REM   administrator's data; GET /myself (02.Introduction/03.myself_GET.bat) answers that. An earlier version of this
REM   script sent a GET, which made it a copy of that one. 02.Introduction/05.myself_POST.bat makes the same call.
REM - Confirmed directly: wrong credentials, or none, answer 401 with the plain text "Authentication required."
REM   (text/html), not JSON. The script prints the status and that answer, and exits 1.
REM - Exit codes: 0 when the login is accepted (200), 1 for any other status.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.json

echo.
echo Basic authentication: logging in with POST /myself...

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
echo.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
