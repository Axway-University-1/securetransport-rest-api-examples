@echo off
REM ==============================================================================
REM Script Name: 06.myself_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script demonstrates how to log in using basic authentication and a cookie jar,
REM then log out by sending a DELETE request to the `/myself` endpoint.
REM It also verifies session status before and after logout.
REM
REM Usage:
REM 06.myself_DELETE.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The cookie jar is used to persist session state across requests.
REM - Confirmed directly: the login answers 200 {"message": "Logged in"}, the read 200, the logout 200 {"message": "Logged out"},
REM   and the read after it 401 with the plain text "Authentication required.": that is how this script knows the session ended.
REM - Every call is checked: a login, a read or a logout that is not 200 prints the status and the answer and ends the script
REM   with exit 1; so does a last read that is still 200 (the session did not end). The jar is left in the folder, as before.
REM - Exit codes: 0 when the session was opened, read, closed and then refused (401 or 403), 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.json
SET LOGIN_HEADERS=%TEMP%\login_headers_%RANDOM%.tmp

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%LOGIN_HEADERS%" DEL "%LOGIN_HEADERS%"
EXIT /B %RC%

:main
REM Authenticate and store session
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

REM Verify session is active
SET METHOD=GET
CALL :session_call
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"

REM Log out
SET METHOD=DELETE
CALL :session_call
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"

REM Verify session is terminated: the server must now refuse the jar
SET METHOD=GET
CALL :session_call
SET ENDED=
IF "%HTTP_CODE%"=="401" SET ENDED=yes
IF "%HTTP_CODE%"=="403" SET ENDED=yes
IF NOT "%ENDED%"=="yes" (
    echo.
    echo The session is still open: HTTP %HTTP_CODE%
    IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM One call of the session in cookie.jar, with the method in METHOD; the status is left in HTTP_CODE, the answer in RESPONSE_FILE
REM ------------------------------------------------------------------------------
:session_call
SET HTTP_CODE=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -L --cookie cookie.jar -X %METHOD% "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"') DO SET HTTP_CODE=%%C
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
