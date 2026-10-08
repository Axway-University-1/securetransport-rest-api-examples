@echo off
REM ==============================================================================
REM Script Name: 07.accounts_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes accounts using the `/accounts/{name}` endpoint.
REM For each account it first reads it, to say what it is about to delete. If it exists, the account is deleted.
REM Otherwise a message is printed.
REM
REM By default it cleans up the three accounts created by 02.accounts_POST.bat.
REM
REM Usage:
REM 07.accounts_name_DELETE.bat [NAME...]
REM
REM   NAME  the accounts to delete (default example_user, example_service and example_template, the ones 02.accounts_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script deletes data. Check the account names before running it: any account can be named, and the delete cannot be undone.
REM   Deleting an account removes its certificates and subscriptions but leaves its home folder, with its files, on disk (see st-api-gotchas).
REM - Each account is read first and what it is (type, home folder, uid) is printed, so that it can be created again with 02.accounts_POST.bat or by hand.
REM - PowerShell is used to URL-encode each name and read the account, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an account that is not there is 404 on the read and on the delete.
REM - Exit codes: 0 when every account named was deleted or was not there, 1 when the server refused one (the others are still tried), 2 when a name is empty (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET FAILED=0
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json
IF [%1]==[] (
    FOR %%A IN (example_user example_service example_template) DO CALL :delete_account %%A
    GOTO done
)
REM Nothing is sent until every name is known to be a name
SET ARGS_OK=yes
FOR %%A IN (%*) DO IF "%%~A"=="" SET ARGS_OK=
IF NOT "%ARGS_OK%"=="yes" (
    echo An account name must not be empty.
    echo Usage: 07.accounts_name_DELETE.bat [NAME...]
    EXIT /B 2
)
FOR %%A IN (%*) DO CALL :delete_account "%%~A"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %FAILED%

REM ------------------------------------------------------------------------------
REM Reads the account named in %1, says what it is, and deletes it if it exists
REM ------------------------------------------------------------------------------
:delete_account
SET ACCOUNT_TO_CHECK=%~1
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ACCOUNT_TO_CHECK)"') DO SET NAME_URI=%%E

REM Let's say that we want to delete an Account.
REM For the purpose we will first read it, with a few fields only, to say what we are deleting.
REM If it exists, we will delete it. Otherwise we print a message that it doesn't exist.
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%NAME_URI%" --data-urlencode "fields=type,homeFolder,uid" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="404" (
    echo Account %ACCOUNT_TO_CHECK% does not exist.
    EXIT /B 0
)
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %ACCOUNT_TO_CHECK%: HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
    EXIT /B 0
)
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Deleting Account: {0} (type {1}, home folder {2}, uid {3})' -f $env:ACCOUNT_TO_CHECK, $a.type, $a.homeFolder, $a.uid"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
)
EXIT /B 0
