@echo off
REM ==============================================================================
REM Script Name: 01.myself_cookie_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script performs basic authentication against the API using a cookie
REM jar to persist session information. It reduces the need for repeated
REM authentication across multiple requests.
REM
REM Usage:
REM call 01_myself_cookie_POST.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - The cookie jar file will store session data for reuse.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

echo.
echo Basic authentication with cookie jar to reduce further authentications...

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

REM Authenticate and store session in cookie jar
set LOGIN_HEADERS=login_headers.tmp
curl -k --cookie-jar cookie.jar -D "%LOGIN_HEADERS%" -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

REM CSRF is enforced on session-cookie calls from the 20230525 release
REM onward. The token comes back once, in this login response's own
REM csrfToken header, and must be sent back on every later call in the
REM session - a Basic auth call carrying no cookie is exempt, but this
REM script keeps a session, so it is not.
FOR /F "tokens=2 delims=: " %%C IN ('findstr /I "^csrfToken:" "%LOGIN_HEADERS%"') DO SET CSRF_TOKEN=%%C
del "%LOGIN_HEADERS%"

REM Reuse session to make a GET request
curl -k --cookie cookie.jar -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -H "csrfToken: %CSRF_TOKEN%"
