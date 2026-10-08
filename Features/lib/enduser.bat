@echo off
REM ==============================================================================
REM Script Name: enduser.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Helpers for the End User API, shared across Features/. Unlike the Admin API, the
REM End User API needs a
REM real login: POST /myself with the account's credentials returns a session
REM cookie and a csrfToken header, and every later call sends both back.
REM
REM Reads EU_ACCOUNT, EU_ACCOUNT_PASSWORD and EU_ENDUSER_PORT - neutral names, not
REM any one feature's own prefix. Each feature's settings.bat sets these as
REM aliases of its own prefixed variables before this is CALLed.
REM
REM Usage:
REM CALL enduser.bat login
REM CALL enduser.bat call METHOD PATH CONTENT_TYPE [DATA_FILE]
REM CALL enduser.bat logout
REM
REM   login    logs in as the test account. Sets EU_JAR and EU_CSRF.
REM   call     makes a call in that session. The response body is in EU_BODY_FILE
REM            and the HTTP code in EU_CODE. ERRORLEVEL is 0 only for a 2xx code.
REM            Each segment of PATH is URL-encoded (see admin_calls.bat), so a file
REM            name from a listing with a space or a # in it reaches the server whole.
REM   logout   DELETE /myself and forget the session.
REM
REM Notes:
REM - The port is EU_ENDUSER_PORT, not the Admin port.
REM - Confirmed directly (5.5-20260924): a file name from a listing with a # in it, put into the URL
REM   as it is, cuts the path short: DELETE /files/dir/a#1.txt asks for /dir/a and is a 404 "Unable
REM   to delete file: /dir/a. (file not found)". A space makes curl send nothing (code 000). With each
REM   segment encoded (a%231.txt, my%20file%231.txt) the GET and the DELETE both work.
REM - A path with a ? in it cannot carry a query string: the ? is encoded like the
REM   rest. No example here needs one.
REM - Needs admin_calls.bat, next to this file, to encode the path.
REM ==============================================================================

GOTO :%~1

:login
SET EU_JAR=%TEMP%\ar_eu_jar_%RANDOM%.txt
SET EU_BODY_FILE=%TEMP%\ar_eu_body_%RANDOM%.txt
SET EU_HEADERS=%TEMP%\ar_eu_headers_%RANDOM%.txt
SET EU_CODE=
SET EU_CSRF=
curl -s -k -u "%EU_ACCOUNT%:%EU_ACCOUNT_PASSWORD%" -X POST "https://%ST_SERVER%:%EU_ENDUSER_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
  --cookie-jar "%EU_JAR%" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%"
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%EU_HEADERS%"') DO SET EU_CODE=%%C
FOR /F "tokens=2" %%T IN ('findstr /B /I "csrftoken:" "%EU_HEADERS%"') DO SET EU_CSRF=%%T
IF NOT DEFINED EU_CODE SET EU_CODE=000
IF "%EU_CODE:~0,1%"=="2" (
    IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
    echo Logged in to the End User API as %EU_ACCOUNT%.
    EXIT /B 0
)
echo Could not log in to the End User API as %EU_ACCOUNT% on port %EU_ENDUSER_PORT% (HTTP %EU_CODE%):
IF EXIST "%EU_BODY_FILE%" TYPE "%EU_BODY_FILE%"
echo Response headers, which may say why:
findstr /V /B /I "set-cookie" "%EU_HEADERS%"
IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
IF EXIST "%EU_JAR%" DEL "%EU_JAR%"
EXIT /B 1

:call
SET EU_HEADERS=%TEMP%\ar_eu_headers_%RANDOM%.txt
SET EU_CODE=
CALL "%~dp0admin_calls.bat" encode "%~3"
IF "%~5"=="" (
    curl -s -k -b "%EU_JAR%" -X %~2 "https://%ST_SERVER%:%EU_ENDUSER_PORT%/api/v2.0/%AC_ENCODED_PATH%" ^
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
      -H "csrfToken: %EU_CSRF%" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%"
) ELSE (
    curl -s -k -b "%EU_JAR%" -X %~2 "https://%ST_SERVER%:%EU_ENDUSER_PORT%/api/v2.0/%AC_ENCODED_PATH%" ^
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
      -H "csrfToken: %EU_CSRF%" -H "Content-Type: %~4" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%" --data-binary "@%~5"
)
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%EU_HEADERS%"') DO SET EU_CODE=%%C
IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
IF NOT DEFINED EU_CODE SET EU_CODE=000
IF "%EU_CODE:~0,1%"=="2" EXIT /B 0
EXIT /B 1

:logout
CALL "%~f0" call DELETE myself "" 
echo Logged out (HTTP %EU_CODE%).
IF EXIST "%EU_JAR%" DEL "%EU_JAR%"
IF EXIST "%EU_BODY_FILE%" DEL "%EU_BODY_FILE%"
EXIT /B 0
