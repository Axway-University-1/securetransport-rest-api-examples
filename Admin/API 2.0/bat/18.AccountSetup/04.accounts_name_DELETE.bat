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
REM 04.accounts_name_DELETE.bat [ACCOUNT]
REM
REM   ACCOUNT  the account to remove (default example_setup, which 01.accountSetup_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: deleting the account also deletes its transfer sites
REM   and transfer profiles.
REM - The files in the account's home folder stay on disk. See
REM   05.Accounts/07.accounts_name_DELETE.bat.
REM - Only ever point it at an account you set up. The delete cannot be undone: the account is read first and what it is (type, home folder and uid)
REM   is printed, so that it can be set up again with 01.accountSetup_POST.bat or by hand.
REM - PowerShell is used to URL-encode the name and read the account, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an account that is not there is 404 on the read and on the delete.
REM - Exit codes: 0 when the account was deleted (204) or was not there, 1 when the server refuses or the account cannot be read, 2 when the name
REM   is empty (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

SET "ACCOUNT=%~1"
IF "%ACCOUNT%"=="" SET ACCOUNT=example_setup
SET BAD_ARGS=
IF NOT "%~2"=="" SET BAD_ARGS=yes
powershell -NoProfile -Command "if ($env:ACCOUNT.Trim() -eq '') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 SET BAD_ARGS=yes
IF DEFINED BAD_ARGS (
    echo Usage: 04.accounts_name_DELETE.bat [ACCOUNT]
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ACCOUNT)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\setup_delete_%RANDOM%.json

REM Read it first, with a few fields only, to say what is being deleted
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%ENCODED%" --data-urlencode "fields=type,homeFolder,uid" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="404" (
    echo Account %ACCOUNT% does not exist.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 0
)
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %ACCOUNT%: HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Deleting the account {0} (type {1}, home folder {2}, uid {3}), with its sites and profiles...' -f $env:ACCOUNT, $a.type, $a.homeFolder, $a.uid"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
