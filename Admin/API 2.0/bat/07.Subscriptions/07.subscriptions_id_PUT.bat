@echo off
REM ==============================================================================
REM Script Name: 07.subscriptions_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a subscription, using the `/subscriptions/{id}` endpoint with
REM PUT: it reads the subscription, changes how many pulls it may run at once
REM (maxParallelSitPulls), and sends the whole subscription back.
REM
REM Usage:
REM 07.subscriptions_id_PUT.bat ACCOUNT APPLICATION FOLDER [VALUE]
REM
REM   ACCOUNT      the account that subscribes
REM   APPLICATION  the application it subscribes to
REM   FOLDER       the folder of the subscription
REM   VALUE        the new maxParallelSitPulls, a whole number, 0 or more (default 2; 0 is no limit)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - It prints the value before, to put it back with.
REM - PUT replaces the whole subscription. Confirmed directly: a body with only the type, account,
REM   application and folder answers 204 and silently drops the transfer configurations (the pull
REM   sites), the flow attributes and every setting it leaves out. That is why the subscription is
REM   read first and sent back with one field changed. `metadata`, the read-only links, is left out.
REM - Confirmed directly: a success answers 204, with no body, and the same subscription sent back
REM   unchanged changes nothing. An id that is not one is 400 "Subscription for ID: X not found", not
REM   the 404 the reference lists (GET, PATCH and DELETE answer 404). A body with no `type` is 400
REM   "Invalid discriminator value."; another type is 400 with a misleading "Unsupported parameter -
REM   postClientDownloads". An `account` that does not exist is 404 (with a transfer configuration in
REM   the body, a bare 403 "unable to comply"); an `application` other than the
REM   subscription's is accepted (204) and ignored; another `folder` moves the subscription. A negative
REM   maxParallelSitPulls is 400, a word is 400 "Cannot parse 'abc' to Integer.".
REM - A transfer configuration sent without its `id` is stored with a new one, and one sent with an id
REM   that no longer exists is 400 "you are trying to update transfer configuration with id X that
REM   does not exists": read the subscription again before sending it back. fileRetentionPeriod
REM   (0 to 36500) needs a transfer site: 400 "Cannot set file retention period without setting
REM   transfer site." without one. A flow attribute key must start with `userVars.`, hold only
REM   letters, digits, `.` and `_`, and not repeat `userVars.`; its value is 1 to 4000 characters.
REM - PowerShell is used to read the id and edit the subscription, in place of jq.
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
SET VALUE=%~4
IF "%VALUE%"=="" SET VALUE=2
powershell -NoProfile -Command "if ($env:VALUE -match '^[0-9]{1,9}$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo VALUE is a whole number, 0 or more, not %VALUE%.
    EXIT /B 2
)
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
SET SUBSCRIPTION_FILE=%TEMP%\subscription_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SUBSCRIPTION_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SUBSCRIPTION_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the subscription %SUBSCRIPTION_ID%.
    IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\subscription_body_%RANDOM%.json
SET NONE_TEXT=(not set)
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$s = Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json; if ($null -eq $s.maxParallelSitPulls) { $env:NONE_TEXT } else { $s.maxParallelSitPulls }"') DO echo maxParallelSitPulls of the subscription is now %%D.
powershell -NoProfile -Command "$s = Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json; $s.maxParallelSitPulls = [int]$env:VALUE; $s.PSObject.Properties.Remove('metadata'); $s | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%SUBSCRIPTION_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 07.subscriptions_id_PUT.bat ACCOUNT APPLICATION FOLDER [VALUE]
EXIT /B 2
