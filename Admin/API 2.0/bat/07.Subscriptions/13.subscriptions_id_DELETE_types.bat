@echo off
REM ==============================================================================
REM Script Name: 13.subscriptions_id_DELETE_types.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes the subscriptions that 12.subscriptions_POST_types.bat creates, and
REM the applications they used, using the `/subscriptions/{id}` endpoint. It
REM demonstrates:
REM - Looking up the id of a subscription by account, application and folder
REM - Deleting it with purge=true, which also removes the subscription's folder
REM - Deleting the application, once nothing subscribes to it
REM
REM Usage:
REM 13.subscriptions_id_DELETE_types.bat [ACCOUNT]
REM
REM   ACCOUNT  the account that was subscribed (default john)
REM
REM Risk: write - deletes the subscriptions of 12 and, with purge=true, their folders
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It only touches the applications ExampleBasicApplication, ExampleHumanSystemApplication,
REM   ExampleMBFTApplication and ExampleStandardRouterApplication and the subscriptions of the account
REM   on them, on the folders /example_Basic, /example_HumanSystem, /example_MBFT and
REM   /example_StandardRouter. Files in those folders are deleted with them.
REM - Confirmed directly: `?purge=true` removes the folder of the subscription from the account's home
REM   folder; without it the folder stays. The answer is 204 either way. The applications are deleted
REM   after their subscription: an application with a subscription is 400 "has active subscriptions".
REM - PowerShell is used to picks the subscription out of the response, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET FAILED=0

FOR %%T IN (Basic HumanSystem MBFT StandardRouter) DO CALL :delete_one %%T
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

:delete_one
SET TYPE=%1
SET APPLICATION=Example%TYPE%Application
SET FOLDER=/example_%TYPE%
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
IF "%FOUND%"=="1" (
    CALL :delete_subscription
) ELSE (
    echo Found %FOUND% subscriptions of the account %ACCOUNT% on the application %APPLICATION% and the folder %FOLDER%; none deleted.
    IF NOT "%FOUND%"=="0" SET FAILED=1
)

echo Deleting the application '%APPLICATION%'...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE ^
  "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%APPLICATION%" ^
  -H "accept: */*" -H "%REFERER_HEADER%"
EXIT /B 0

:delete_subscription
echo Deleting the subscription on '%FOLDER%' (%SUBSCRIPTION_ID%), and its folder...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%SUBSCRIPTION_ID%?purge=true" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" SET FAILED=1
EXIT /B 0
