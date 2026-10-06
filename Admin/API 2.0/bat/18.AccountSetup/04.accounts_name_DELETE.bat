@echo off
REM ==============================================================================
REM Script Name: 04.accounts_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script removes the account 01.accountSetup_POST.bat sets up, using the
REM `/accounts/{name}` endpoint. /accountSetup has no DELETE of its own:
REM deleting the account removes what was set up with it.
REM
REM Usage:
REM 04.accounts_name_DELETE.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: deleting the account also deletes its transfer sites
REM   and transfer profiles.
REM - The files in the account's home folder stay on disk. See
REM   05.Accounts\07.accounts_name_DELETE.bat.
REM - Only ever point it at an account you set up.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=example_setup

echo Deleting the account %ACCOUNT%, with its sites and profiles...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
