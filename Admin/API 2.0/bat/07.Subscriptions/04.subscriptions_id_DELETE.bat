@echo off
REM ==============================================================================
REM Script Name: 04.subscriptions_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes subscriptions using the `/subscriptions/{id}` endpoint,
REM and then the application they used. It demonstrates:
REM - Looking up the id of a subscription by account, application and folder
REM - Deleting the subscription by that id
REM - Deleting the application, once nothing subscribes to it
REM - Printing the HTTP code of each delete, and exiting 1 when the server refuses one
REM
REM Usage:
REM 04.subscriptions_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up what 02.subscriptions_POST.bat and
REM   03.subscriptions_POST_triggerfile.bat create for the account "john": the
REM   subscriptions on /inbox and /inbox-trigger, and the application
REM   AdvancedRoutingApplication. Only ever point it at what you created.
REM - Delete a composite route that is linked to a subscription first. See
REM   09.CompositeRoutes/07.routes_id_DELETE.bat.
REM - The subscription is looked up with the exact account and application (both filters are exact) and the folder is compared on what
REM   comes back; a subscription that is not there is reported and skipped, and two that match are not deleted (exit 1). A plain DELETE
REM   leaves the folder in the account's home folder: 07.Subscriptions/13 shows `purge=true`, which removes it.
REM - The application that is not there (404) is reported and skipped. One that still has a subscription is refused, 400 "has active
REM   subscriptions", and the script exits 1.
REM - PowerShell is used to pick the subscription out of the response, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Subscription with id X not found or not accessible.",
REM   and an application that is not there is a JSON 404 too, "Application with name X not found or not accessible.".
REM - Exit codes: 0 when everything was deleted or was not there, 1 when the server refuses a lookup or a delete, or two subscriptions
REM   match. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0

IF NOT "%~1"=="" (
    echo Usage: 04.subscriptions_id_DELETE.bat
    EXIT /B 2
)

SET ACCOUNT=john
SET APPLICATION=AdvancedRoutingApplication
SET RESPONSE_FILE=%TEMP%\subscriptions_%RANDOM%.json
SET FAILED=0

FOR %%F IN ("/inbox" "/inbox-trigger") DO CALL :delete_subscription "%%~F"

echo Deleting the application '%APPLICATION%'...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:APPLICATION)"') DO SET APPLICATION_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/applications/%APPLICATION_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="204" (
    echo Deleted the application '%APPLICATION%'.
) ELSE IF "%HTTP_CODE%"=="404" (
    echo There is no application '%APPLICATION%'.
) ELSE (
    CALL :show_error
    SET FAILED=1
)

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Looks up the subscription of the account on the application and the folder named in %1, and deletes it
REM ------------------------------------------------------------------------------
:delete_subscription
SET "FOLDER=%~1"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/subscriptions" --data-urlencode "account=%ACCOUNT%" --data-urlencode "application=%APPLICATION%" --data-urlencode "fields=id,application,folder" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not look up the subscriptions of '%ACCOUNT%': HTTP %HTTP_CODE%
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
SET FOUND=0
SET SUBSCRIPTION_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null -and $_.application -ceq $env:APPLICATION -and $_.folder -ceq $env:FOLDER }) | ForEach-Object { $_.id }"') DO (
    SET /A FOUND+=1
    SET SUBSCRIPTION_ID=%%I
)
IF "%FOUND%"=="0" (
    echo The account '%ACCOUNT%' has no subscription on '%FOLDER%'.
    EXIT /B 0
)
IF NOT "%FOUND%"=="1" (
    echo The account '%ACCOUNT%' has %FOUND% subscriptions on '%FOLDER%' and '%APPLICATION%'; none deleted.
    SET FAILED=1
    EXIT /B 0
)
echo Deleting the subscription on '%FOLDER%' (%SUBSCRIPTION_ID%)...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:SUBSCRIPTION_ID)"') DO SET SUBSCRIPTION_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/subscriptions/%SUBSCRIPTION_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
echo Deleted the subscription on '%FOLDER%'.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
