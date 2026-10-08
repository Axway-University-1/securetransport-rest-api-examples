@echo off
REM ==============================================================================
REM Script Name: 10.subscriptions_id_operations_POST_clearPullHistory.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script clears the pull history of a subscription, using the
REM `/subscriptions/{id}/operations` endpoint with operation=ClearPullHistory. A
REM subscription that keeps a pull history does not pull a file twice; once the
REM history is cleared, the next pull fetches the files again.
REM
REM Usage:
REM 10.subscriptions_id_operations_POST_clearPullHistory.bat ACCOUNT APPLICATION FOLDER
REM
REM   ACCOUNT      the account that subscribes
REM   APPLICATION  the application it subscribes to
REM   FOLDER       the folder of the subscription
REM
REM Risk: write - forgets which files were pulled, so the next pull fetches them again
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - The pull history is kept only when the subscription's fileRetentionPeriod is more than 0
REM   (set it with a PUT, 07.subscriptions_id_PUT.bat shows how; it needs an SFTP pull site).
REM - It answers 202 and clears in the background: the message says the clearing was submitted.
REM - Confirmed directly: with a retention of 5 days, a file pulled and then deleted from the folder was
REM   not pulled by the next Pull (09.subscriptions_id_operations_POST_pull.bat), and was pulled again
REM   after ClearPullHistory. On a subscription with no history the call is 202 as well.
REM   The operation takes an optional body `{"type":"clearPullHistory","fileRetentionPeriod":N}`
REM   (0 to 36500, else 400); it was accepted, and what it changes was not seen, so this script sends
REM   none. The operation name is case sensitive: `clearpullhistory` and unknown ones are 404.
REM - PowerShell is used to read the id and print the message, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
SET APPLICATION=%~2
SET FOLDER=%~3
IF "%ACCOUNT%"=="" GOTO :usage
IF "%APPLICATION%"=="" GOTO :usage
IF "%FOLDER%"=="" GOTO :usage
SET LOOKUP_FILE=%TEMP%\subscription_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "application=%APPLICATION%" --data-urlencode "fields=id,application,folder" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET SUBSCRIPTION_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.application -ceq $env:APPLICATION -and $_.folder -ceq $env:FOLDER }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SUBSCRIPTION_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% subscriptions of the account %ACCOUNT% on the application %APPLICATION% and the folder %FOLDER%; this script acts on exactly one.
    EXIT /B 1
)
SET RESPONSE_FILE=%TEMP%\subscription_clear_answer_%RANDOM%.json

echo Clearing the pull history of the subscription of '%ACCOUNT%' on '%APPLICATION%', folder '%FOLDER%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%SUBSCRIPTION_ID%/operations?operation=ClearPullHistory" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="202" (
    powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).message"
) ELSE (
    type "%RESPONSE_FILE%"
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="202" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 10.subscriptions_id_operations_POST_clearPullHistory.bat ACCOUNT APPLICATION FOLDER
EXIT /B 2
