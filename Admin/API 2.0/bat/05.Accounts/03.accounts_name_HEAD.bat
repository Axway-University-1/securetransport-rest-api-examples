@echo off
REM ==============================================================================
REM Script Name: 03.accounts_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether an account exists using the HEAD method on the
REM `/accounts/{name}` endpoint.
REM It demonstrates:
REM - Sending a HEAD request
REM - Capturing the HTTP response code
REM - Acting on the result
REM
REM Usage:
REM 03.accounts_name_HEAD.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - HEAD returns the headers only, which makes it a cheap existence check.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT_TO_CHECK=UserAccount
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

echo Checking whether the account '%ACCOUNT_TO_CHECK%' exists...
curl -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ACCOUNT_TO_CHECK%" -H "accept: */*" -H "%REFERER_HEADER%"

REM
REM If you want to parse the response code, here is an example how to do it.
REM The RESPONSE_CODE variable will contain our HTTP response code.
REM
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ACCOUNT_TO_CHECK%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C

echo HTTP response code: %RESPONSE_CODE%

REM And this is the if statement that prints "Account Exists" when the code is 200
IF "%RESPONSE_CODE%"=="200" (
    echo Account Exists
)

REM An alternative version with an if-else construction
IF "%RESPONSE_CODE%"=="200" (
    echo Account Exists
) ELSE (
    echo Account does not exist
)
