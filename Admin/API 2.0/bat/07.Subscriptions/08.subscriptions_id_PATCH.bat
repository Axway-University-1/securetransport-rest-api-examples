@echo off
REM ==============================================================================
REM Script Name: 08.subscriptions_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a subscription, using the
REM `/subscriptions/{id}` endpoint with PATCH: a JSON Patch document that adds one
REM flow attribute (a userVars key that the routes of the subscription can read).
REM Unlike PUT (07.subscriptions_id_PUT.bat), it sends only what changes.
REM
REM Usage:
REM 08.subscriptions_id_PATCH.bat ACCOUNT APPLICATION FOLDER [VALUE]
REM
REM   ACCOUNT      the account that subscribes
REM   APPLICATION  the application it subscribes to
REM   FOLDER       the folder of the subscription
REM   VALUE        the value of the flow attribute userVars.example_note (default example)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - It prints the value before, to put it back with.
REM - Confirmed directly: a success answers 204, with no body. `add` sets a flow attribute whether
REM   or not it exists (an existing value is overwritten); `replace` of one that does not exist is
REM   400 `Missing field "userVars.x"`, of one that does is 204; `remove` deletes it. `replace` of a
REM   field that is null (maxParallelSitPulls) works, and `remove` of it sets it back to null. The
REM   value cannot be empty or blank (400 "Attribute value cannot be empty.") or over 4000
REM   characters. `type` is read only (400 "Patch operation on read only or discriminator fields is
REM   not permitted."); `replace` of `/id` and of `/application` answer 204 and change nothing; of
REM   `/account` to one that does not exist 404; of `/folder` it moves the subscription. A path
REM   that does not exist is 400 `Missing field "nosuch"`, an empty patch is 204, `add` to
REM   `/transferConfigurations/-` adds a transfer configuration, an unknown id is a JSON 404.
REM - PowerShell is used to read the id and build the patch, in place of jq.
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
IF "%VALUE%"=="" SET VALUE=example
SET KEY=userVars.example_note
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
SET BODY_FILE=%TEMP%\subscription_patch_%RANDOM%.json
SET NONE_TEXT=(not set)
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$s = Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json; $v = $s.flowAttributes.PSObject.Properties[$env:KEY]; if ($v) { $v.Value } else { $env:NONE_TEXT }"') DO echo The flow attribute %KEY% is now %%D.
IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"
powershell -NoProfile -Command "$op = [ordered]@{ op = 'add'; path = '/flowAttributes/' + $env:KEY; value = $env:VALUE }; ConvertTo-Json -InputObject @($op) -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%SUBSCRIPTION_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 08.subscriptions_id_PATCH.bat ACCOUNT APPLICATION FOLDER [VALUE]
EXIT /B 2
