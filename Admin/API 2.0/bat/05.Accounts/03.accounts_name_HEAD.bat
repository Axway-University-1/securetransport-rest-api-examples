@echo off
REM ==============================================================================
REM Script Name: 03.accounts_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether an account exists, using the `/accounts/{name}` endpoint with the HEAD method.
REM It demonstrates:
REM - HEAD, which returns the headers only and so is a cheap existence check
REM - Reading the HTTP code with curl itself (`-w`), and acting on it
REM
REM Usage:
REM 03.accounts_name_HEAD.bat [NAME]
REM
REM   NAME  the account (default example_user, the one 02.accounts_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: 200 when the account exists and 404 when it does not, with no body either way.
REM - Exit codes: 0 when the account exists, 1 when it does not (404) or the server answers otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E

REM The HTTP code comes from curl itself. A bare --head would print the headers instead.
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%

IF "%HTTP_CODE%"=="200" (
    echo Account Exists
    EXIT /B 0
)
IF "%HTTP_CODE%"=="404" (
    echo Account does not exist
    EXIT /B 1
)
echo Could not tell whether the account exists.
EXIT /B 1
