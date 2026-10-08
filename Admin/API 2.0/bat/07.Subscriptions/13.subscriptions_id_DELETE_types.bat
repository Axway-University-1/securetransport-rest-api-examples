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
REM - The status of each call is read with `curl -w`, and a delete the server refuses (a 4xx or 5xx) makes the exit code 1; the next ones are
REM   still tried. A subscription or an application that is not there (404) is reported, not an error.
REM - PowerShell is used to pick the subscription out of the response, in place of jq.
REM - Exit codes: 0 when everything was deleted or was not there, 1 when the server refuses a lookup or a delete, or two subscriptions match,
REM   2 when the account is empty or there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
IF NOT "%~2"=="" (
    echo Usage: 13.subscriptions_id_DELETE_types.bat [ACCOUNT]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\subscription_response_%RANDOM%.json
SET FAILED=0

FOR %%T IN (Basic HumanSystem MBFT StandardRouter) DO CALL :delete_one %%T

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Deletes the subscription of the account on the application of the type %1, with its folder, and then the application
REM ------------------------------------------------------------------------------
:delete_one
SET TYPE=%1
SET APPLICATION=Example%TYPE%Application
SET FOLDER=/example_%TYPE%

REM The account and application filters are exact; the application and the folder are compared again here, on what comes back
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "application=%APPLICATION%" --data-urlencode "fields=id,application,folder" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not look up the subscriptions of '%ACCOUNT%' on '%APPLICATION%': HTTP %HTTP_CODE%
    CALL :show_error
    SET FAILED=1
    GOTO delete_application
)
SET FOUND=0
SET SUBSCRIPTION_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null -and $_.application -ceq $env:APPLICATION -and $_.folder -ceq $env:FOLDER }) | ForEach-Object { $_.id }"') DO (
    SET /A FOUND+=1
    SET SUBSCRIPTION_ID=%%I
)
IF "%FOUND%"=="1" GOTO delete_subscription
echo Found %FOUND% subscriptions of the account %ACCOUNT% on the application %APPLICATION% and the folder %FOLDER%; none deleted.
IF NOT "%FOUND%"=="0" SET FAILED=1
GOTO delete_application

:delete_subscription
echo Deleting the subscription on '%FOLDER%' (%SUBSCRIPTION_ID%), and its folder...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:SUBSCRIPTION_ID)"') DO SET SUBSCRIPTION_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%SUBSCRIPTION_URI%?purge=true" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET FAILED=1
)

:delete_application
echo Deleting the application '%APPLICATION%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%APPLICATION%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="404" (
    echo There is no application '%APPLICATION%'.
    EXIT /B 0
)
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET FAILED=1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
