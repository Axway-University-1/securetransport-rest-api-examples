@echo off
REM ==============================================================================
REM Script Name: 07.accounts_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes accounts using the `/accounts/{name}` endpoint.
REM For each account it first checks whether the account exists with the HEAD
REM method. If it exists, the account is deleted. Otherwise a message is printed.
REM
REM It cleans up the three accounts created by 02.accounts_POST.bat.
REM
REM Usage:
REM 07.accounts_name_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script deletes data. Check the account names before running it.
REM - The work is done in a CALL subroutine. Each CALL is its own statement, so
REM   the variables set inside it can be read normally, without the need for
REM   delayed expansion.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

FOR %%A IN (UserAccount,ServiceAccount,TemplateAccount) DO CALL :delete_account %%A

EXIT /B 0

REM ------------------------------------------------------------------------------
REM Deletes the account named in %1, if it exists
REM ------------------------------------------------------------------------------
:delete_account
SET ACCOUNT_TO_CHECK=%1

FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ACCOUNT_TO_CHECK%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C

IF "%RESPONSE_CODE%"=="200" (
    echo Deleting Account: %ACCOUNT_TO_CHECK%
    curl -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ACCOUNT_TO_CHECK%" -H "accept: */*" -H "%REFERER_HEADER%"
) ELSE (
    echo Account %ACCOUNT_TO_CHECK% does not exist.
)
EXIT /B
