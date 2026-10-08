@echo off
REM ==============================================================================
REM Script Name: 02.transactionManager_operations_POST_stop.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script STOPS the Transaction Manager (TM) of the whole server, using the `/transactionManager/operations`
REM endpoint with operation=stop. The Transaction Manager runs the transfers and the routing; with it stopped the server
REM takes no more of them. There is NO start operation: it cannot be started again through the API.
REM It demonstrates:
REM - A graceful stop (the default): the events in progress are processed first, within a timeout in seconds
REM - An immediate stop (GRACEFUL false)
REM - A guard: nothing is sent unless the first argument is the confirmation word
REM
REM Usage:
REM 02.transactionManager_operations_POST_stop.bat stop-the-transaction-manager [GRACEFUL [TIMEOUT]]
REM
REM   stop-the-transaction-manager
REM                 the confirmation: this exact word, required. Without it, or with any other
REM                 word, the script prints this usage, sends NOTHING and exits 2
REM   GRACEFUL      true (default) or false
REM   TIMEOUT       seconds to let the events in progress finish, a whole number, only with GRACEFUL true
REM                 (optional; the server's TransactionManager.GracefulShutdownTimeout option when left out)
REM
REM Risk: disruptive - stops the Transaction Manager of the whole server; cannot be undone through the API
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to read the answer, in place of jq.
REM - THIS WAS NOT RUN AGAINST A SERVER. It stops the Transaction Manager of the whole server, and there is no operation to start it
REM   again through the API (see below), so no lab was stopped to see the answer. It was written from the reference and from
REM   `python/python3/stGraceful.py`, which makes the same call (`operation=stop&graceful=true&timeout=N`, no body), and is tested
REM   offline with a stub `curl` that never reaches a server (tests/checks/test_bash_admin_api.bat).
REM - Run it only on a server you can restart, to see the answer. What brings the Transaction Manager back is a restart of the
REM   server's own services, outside this API. Check it afterwards with 01.transactionManager_GET.bat.
REM - Nothing is sent unless the first argument is exactly `stop-the-transaction-manager`. There is no default and no environment variable
REM   that stands in for it. The arguments are checked before anything is sent: a bad one exits 2.
REM - The reference: `operation` is required and can only be `stop`; `graceful` is a boolean, false when left out (an immediate stop;
REM   this script sends it always, and makes true the default); `timeout` is in seconds, and the events it lets finish are the
REM   server side transfers, the post processing actions and the advanced routing operations. The answer is 200 with
REM   `{"message": ..., "isSuccessful": true or false}`; this script prints both and exits 0 on 200 with isSuccessful not false.
REM - Recorded in st-api-gotchas by an earlier session, not repeated here: `operation=start` is refused, 400
REM   `stopGracefully.arg1 must match "(?i)(stop)"`. Unlike a daemon, a server or a cluster service, only stop exists.
REM   The stop operation itself was NEVER sent to the lab while covering this resource, not even with a wrong value.
REM - Exit codes: 0 when the server answered 200 and the stop worked, 1 when it refuses or says it did not work, 2 when the confirmation
REM   or an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transactionManager
SET CONFIRMATION=stop-the-transaction-manager
SET GRACEFUL=%~2
IF "%GRACEFUL%"=="" SET GRACEFUL=true
SET TIMEOUT=%~3
SET USAGE=Usage: 02.transactionManager_operations_POST_stop.bat %CONFIRMATION% [GRACEFUL [TIMEOUT]]

IF NOT "%~1"=="%CONFIRMATION%" (
    echo This stops the Transaction Manager of the whole server, and it cannot be started again through the API.
    echo Nothing was sent. To go on, give the word %CONFIRMATION% as the first argument.
    echo %USAGE%
    EXIT /B 2
)
IF NOT "%GRACEFUL%"=="true" IF NOT "%GRACEFUL%"=="false" GOTO usage
IF NOT "%TIMEOUT%"=="" (
    FOR /F "delims=0123456789" %%X IN ("%TIMEOUT%") DO GOTO usage
    IF NOT "%GRACEFUL%"=="true" GOTO usage
)
IF NOT "%~4"=="" GOTO usage

SET URL=%MAIN_URL%/operations?operation=stop^&graceful=%GRACEFUL%
IF NOT "%TIMEOUT%"=="" SET URL=%URL%^&timeout=%TIMEOUT%
SET RESPONSE_FILE=%TEMP%\tm_%RANDOM%.json

echo Stopping the Transaction Manager (graceful: %GRACEFUL%)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" GOTO refused
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.message) { $r.message } else { $r }; if ($null -ne $r.isSuccessful -and ([string]$r.isSuccessful).ToLower() -eq 'false') { exit 1 } else { exit 0 }"
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
