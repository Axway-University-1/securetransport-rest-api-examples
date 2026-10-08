@echo off
REM ==============================================================================
REM Script Name: 01.myself_cookie_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs basic authentication against the API using a cookie jar
REM to persist session information. It reduces the need for repeated authentication
REM across multiple requests.
REM
REM Usage:
REM 01.myself_cookie_POST.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The cookie jar file will store session data for reuse.
REM - Confirmed directly: the login answers 200 {"message": "Logged in"} and a csrfToken header; the read that follows
REM   with the jar answers 200 with the administrator's data. A refused login (401, "Authentication required." as plain
REM   text) or a refused read prints the status and the answer and exits 1; the jar is removed when the login fails.
REM - Exit codes: 0 when both calls answer 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

echo.
echo Basic authentication with cookie jar to reduce further authentications...

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.json
SET LOGIN_HEADERS=%TEMP%\login_headers_%RANDOM%.tmp

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%LOGIN_HEADERS%" DEL "%LOGIN_HEADERS%"
EXIT /B %RC%

:main
REM Authenticate and store session in cookie jar
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k --cookie-jar cookie.jar -D "%LOGIN_HEADERS%" -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    IF EXIST cookie.jar DEL cookie.jar
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"

REM CSRF is enforced on session-cookie calls from the 20230525 release
REM onward. The token comes back once, in this login response's own
REM csrfToken header, and must be sent back on every later call in the
REM session - a Basic auth call carrying no cookie is exempt, but this
REM script keeps a session, so it is not.
FOR /F "tokens=2 delims=: " %%C IN ('findstr /I "^csrfToken:" "%LOGIN_HEADERS%"') DO SET CSRF_TOKEN=%%C

REM Reuse session to make a GET request
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k --cookie cookie.jar -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"') DO SET HTTP_CODE=%%C
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
