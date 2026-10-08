@echo off
REM ==============================================================================
REM Script Name: 04.accounts_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves one account using the `/accounts/{name}` endpoint.
REM It demonstrates:
REM - Retrieving everything about an account
REM - Selecting individual fields
REM - That a field specific to one account type needs the type in the request
REM
REM Usage:
REM 04.accounts_name_GET.bat [NAME]
REM
REM   NAME  the account (default example_user, the one 02.accounts_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The type is always returned, even when it is not listed in the fields.
REM - Confirmed directly (5.5-20260924): `fields=addressBookSettings` without `type=user` is refused, 400 "Field addressBookSettings does not exist." (older notes say it answers
REM   only the type); with `type=user` it answers the settings. That third call is the demonstration of it, so its refusal is shown and does not stop the script. The whole object,
REM   read with no `fields`, carries `addressBookSettings` without any `type`.
REM - Exit codes: 0 when every call but that one answered 200, 1 when one did not.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json

REM Simple GET to retrieve everything about a specific account
CALL :get_account ""
IF ERRORLEVEL 1 EXIT /B 1

REM GET only the name, uid, and gid
REM Pay attention that the type is also returned no matter that it is not specified in the fields
CALL :get_account "?fields=name,uid,gid"
IF ERRORLEVEL 1 EXIT /B 1

REM If we want to receive fields that are not common to all account types, but are
REM specific to the user one, we have to specify the type.
REM Let's try with the addressBookSettings and without the type.
CALL :get_account "?fields=addressBookSettings" demo
IF ERRORLEVEL 1 EXIT /B 1

REM And now by specifying the type=user
CALL :get_account "?type=user&fields=addressBookSettings"
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM GET the account with the query string in %1; print the answer, and exit 1 when it is not 200
REM (a call given as demo in %2 is expected to be refused, so its answer is shown and the script goes on)
REM ------------------------------------------------------------------------------
:get_account
SET "QUERY=%~1"
powershell -NoProfile -Command "'GET /api/v2.0/accounts/' + $env:NAME_URI + $env:QUERY"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%%QUERY%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
TYPE "%RESPONSE_FILE%"
echo.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    IF NOT "%~2"=="demo" EXIT /B 1
)
EXIT /B 0
