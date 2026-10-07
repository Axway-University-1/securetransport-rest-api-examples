@echo off
REM ==============================================================================
REM Script Name: 06.myself_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script demonstrates how to log in using basic authentication and a
REM cookie jar, then log out by sending a DELETE request to the `/myself` endpoint.
REM It also verifies session status before and after logout.
REM
REM Usage:
REM call 06_myself_DELETE.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - The cookie jar is used to persist session state across requests.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

REM Authenticate and store session
set LOGIN_HEADERS=login_headers.tmp
curl -k --cookie-jar cookie.jar -D "%LOGIN_HEADERS%" -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%"

REM CSRF is enforced on session-cookie calls from the 20230525 release
REM onward. The token comes back once, in this login response's own
REM csrfToken header, and must be sent back on every later call in the
REM session - a Basic auth call carrying no cookie is exempt, but this
REM script keeps a session, so it is not.
FOR /F "tokens=2 delims=: " %%C IN ('findstr /I "^csrfToken:" "%LOGIN_HEADERS%"') DO SET CSRF_TOKEN=%%C
del "%LOGIN_HEADERS%"

REM Verify session is active
curl -k --cookie cookie.jar -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"

REM Log out
curl -k -L --cookie cookie.jar -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"

REM Verify session is terminated
curl -k --cookie cookie.jar -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"
