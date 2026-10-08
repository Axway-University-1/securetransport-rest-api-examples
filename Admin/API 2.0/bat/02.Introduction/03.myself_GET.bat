@echo off
REM ==============================================================================
REM Script Name: 03.myself_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script queries the API to retrieve information about the current user.
REM It performs two GET requests:
REM   1. To fetch full user details.
REM   2. To extract the last password change time from the response.
REM
REM Usage:
REM 03.myself_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The script uses basic authentication and filters JSON output using findstr.
REM - Confirmed directly: GET /myself answers 200 with the administrator's data (loginName, roleName, lastPasswordChangeTime,
REM   ...); refused credentials answer 401 with the plain text "Authentication required.". Either call that is not 200 prints
REM   the status and the answer and ends the script with exit 1.
REM - The second findstr would exit 1 on an answer without lastPasswordChangeTime, so the script ends with exit 0: its exit
REM   code is that of the calls.
REM - Exit codes: 0 when both answers are 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Query the API to get full user information
echo.
echo Querying the API to get information about the current user...
CALL :get_myself
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

REM Query again and filter for last password change time
echo.
echo.
echo Querying the API again and filtering the response to find the last password change time...
CALL :get_myself
IF ERRORLEVEL 1 EXIT /B 1
findstr "lastPasswordChangeTime" "%RESPONSE_FILE%"

REM The findstr above only shows a line: the exit code is that of the calls, which answered 200
EXIT /B 0

REM ------------------------------------------------------------------------------
REM GET /myself into RESPONSE_FILE; returns 1 (after showing why) unless it answers 200
REM ------------------------------------------------------------------------------
:get_myself
SET HTTP_CODE=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
