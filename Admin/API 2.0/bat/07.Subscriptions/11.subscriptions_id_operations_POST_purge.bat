@echo off
REM ==============================================================================
REM Script Name: 11.subscriptions_id_operations_POST_purge.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script purges a subscription's folder, using the `/subscriptions/{id}/operations`
REM endpoint with operation=Purge: the folder and everything in it are removed, and
REM the subscription stays.
REM
REM Usage:
REM 11.subscriptions_id_operations_POST_purge.bat ACCOUNT APPLICATION FOLDER
REM
REM   ACCOUNT      the account that subscribes
REM   APPLICATION  the application it subscribes to
REM   FOLDER       the folder of the subscription
REM
REM Risk: write - deletes the subscription's folder and every file in it
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - This deletes files that cannot be got back. Check the arguments before running it.
REM - Confirmed directly: the answer is 204, with no body. The whole folder goes, not only what is in
REM   it, and the subscription stays (HEAD is still 200); other folders of the account are not touched.
REM   Deleting the subscription with `DELETE /subscriptions/{id}?purge=true` does the same, and without
REM   `purge` the folder is left in the account (13.subscriptions_id_DELETE_types.bat uses purge=true).
REM   The operation name is case sensitive: `purge` is 404.
REM - PowerShell is used to read the id, in place of jq.
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

echo Purging the folder '%FOLDER%' of '%ACCOUNT%' ^(subscription to '%APPLICATION%'^)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%SUBSCRIPTION_ID%/operations?operation=Purge" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 11.subscriptions_id_operations_POST_purge.bat ACCOUNT APPLICATION FOLDER
EXIT /B 2
