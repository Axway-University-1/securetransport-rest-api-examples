@echo off
REM ==============================================================================
REM Script Name: enduser.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Helpers for the End User API. Unlike the Admin API, the End User API needs a
REM real login: POST /myself with the account's credentials returns a session
REM cookie and a csrfToken header, and every later call sends both back.
REM
REM Usage:
REM CALL enduser.bat login
REM CALL enduser.bat call METHOD PATH CONTENT_TYPE [DATA_FILE]
REM CALL enduser.bat logout
REM
REM   login    logs in as the test account. Sets EU_JAR and EU_CSRF.
REM   call     makes a call in that session. The response body is in EU_BODY_FILE
REM            and the HTTP code in EU_CODE. ERRORLEVEL is 0 only for a 2xx code.
REM   logout   DELETE /myself and forget the session.
REM
REM Notes:
REM - The port is AR_ENDUSER_PORT, not the Admin port.
REM ==============================================================================

GOTO :%~1

:login
SET EU_JAR=%TEMP%\ar_eu_jar_%RANDOM%.txt
SET EU_BODY_FILE=%TEMP%\ar_eu_body_%RANDOM%.txt
SET EU_HEADERS=%TEMP%\ar_eu_headers_%RANDOM%.txt
SET EU_CODE=
SET EU_CSRF=
curl -s -k -u "%AR_TEST_ACCOUNT%:%AR_ACCOUNT_PASSWORD%" -X POST "https://%ST_SERVER%:%AR_ENDUSER_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
  --cookie-jar "%EU_JAR%" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%"
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%EU_HEADERS%"') DO SET EU_CODE=%%C
FOR /F "tokens=2" %%T IN ('findstr /B /I "csrftoken:" "%EU_HEADERS%"') DO SET EU_CSRF=%%T
IF "%EU_CODE:~0,1%"=="2" (
    IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
    echo Logged in to the End User API as %AR_TEST_ACCOUNT%.
    EXIT /B 0
)
echo Could not log in to the End User API as %AR_TEST_ACCOUNT% on port %AR_ENDUSER_PORT% (HTTP %EU_CODE%):
IF EXIST "%EU_BODY_FILE%" TYPE "%EU_BODY_FILE%"
echo Response headers, which may say why:
findstr /V /B /I "set-cookie" "%EU_HEADERS%"
IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
IF EXIST "%EU_JAR%" DEL "%EU_JAR%"
EXIT /B 1

:call
SET EU_HEADERS=%TEMP%\ar_eu_headers_%RANDOM%.txt
SET EU_CODE=
IF "%~5"=="" (
    curl -s -k -b "%EU_JAR%" -X %~2 "https://%ST_SERVER%:%AR_ENDUSER_PORT%/api/v2.0/%~3" ^
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
      -H "csrfToken: %EU_CSRF%" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%"
) ELSE (
    curl -s -k -b "%EU_JAR%" -X %~2 "https://%ST_SERVER%:%AR_ENDUSER_PORT%/api/v2.0/%~3" ^
      -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" ^
      -H "csrfToken: %EU_CSRF%" -H "Content-Type: %~4" -D "%EU_HEADERS%" -o "%EU_BODY_FILE%" --data-binary "@%~5"
)
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%EU_HEADERS%"') DO SET EU_CODE=%%C
IF EXIST "%EU_HEADERS%" DEL "%EU_HEADERS%"
IF "%EU_CODE:~0,1%"=="2" EXIT /B 0
EXIT /B 1

:logout
CALL "%~f0" call DELETE myself "" 
echo Logged out (HTTP %EU_CODE%).
IF EXIST "%EU_JAR%" DEL "%EU_JAR%"
IF EXIST "%EU_BODY_FILE%" DEL "%EU_BODY_FILE%"
EXIT /B 0
