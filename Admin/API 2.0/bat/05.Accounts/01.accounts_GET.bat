@echo off
REM ==============================================================================
REM Script Name: 01.accounts_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves accounts using the `/accounts` endpoint.
REM It demonstrates:
REM - Retrieving all accounts
REM - Filtering by account type
REM - Selecting individual fields
REM - Limiting the number of results
REM
REM Usage:
REM 01.accounts_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The type is always returned, even when it is not listed in the fields.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when the answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\accounts_response_%RANDOM%.json

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Simple GET to retrieve all available Accounts
echo Retrieving all accounts...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"

REM GET only the Accounts of type user
REM You can also try with type=template or type=service
REM curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?type=user" -H "accept: */*" -H "%REFERER_HEADER%"

REM GET the User Accounts and receive only the name and home folder in the response
REM Pay attention that the type is also returned no matter that it is not specified in the fields
REM curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?type=user&fields=name,homeFolder" -H "accept: */*" -H "%REFERER_HEADER%"

REM If the result is still big to analyze, you can use the limit parameter to get the first 5 elements
REM curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?type=user&fields=name,homeFolder&limit=5" -H "accept: */*" -H "%REFERER_HEADER%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
