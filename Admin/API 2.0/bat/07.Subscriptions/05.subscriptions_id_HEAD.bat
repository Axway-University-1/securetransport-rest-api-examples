@echo off
REM ==============================================================================
REM Script Name: 05.subscriptions_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a subscription exists, using the `/subscriptions/{id}`
REM endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the
REM subscription's id, so the script looks the id up by account, application and
REM folder first.
REM
REM Usage:
REM 05.subscriptions_id_HEAD.bat [ACCOUNT [APPLICATION [FOLDER]]]
REM
REM   ACCOUNT      the account that subscribes (default john, or ST_EXAMPLE_ACCOUNT)
REM   APPLICATION  the application it subscribes to (default AdvancedRoutingApplication)
REM   FOLDER       the folder of the subscription (default /inbox, which
REM                02.subscriptions_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - Confirmed directly: HEAD answers 200 for a subscription of any type and 404, with no body,
REM   for an id that does not exist. The `account=` and `application=` filters are exact: case
REM   sensitive, with no * wildcard (`EXAMPLE_X` and `example_*` find nothing). `folder=` takes a *.
REM   A second subscription on the same application and folder is 400 "All subscriptions to an
REM   application should have a unique anchor"; a different folder is fine, so one account has
REM   several subscriptions on one application. `type=` with a value that is not a type finds
REM   nothing (no error), `limit=-1` is 400 "The limit should be a positive number or 0.".
REM - The list is not stable: a call can come back without a subscription that exists, so a
REM   "Found 0" is worth one more try before concluding it is not there.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET APPLICATION=%~2
IF "%APPLICATION%"=="" SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=%~3
IF "%FOLDER%"=="" SET FOLDER=/inbox
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

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%SUBSCRIPTION_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The subscription of %ACCOUNT% on %APPLICATION%, folder %FOLDER%, exists, id %SUBSCRIPTION_ID%.
) ELSE (
    echo The subscription of %ACCOUNT% on %APPLICATION%, folder %FOLDER%, id %SUBSCRIPTION_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
