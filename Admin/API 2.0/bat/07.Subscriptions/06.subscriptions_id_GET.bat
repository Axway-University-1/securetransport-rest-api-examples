@echo off
REM ==============================================================================
REM Script Name: 06.subscriptions_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one subscription, using the `/subscriptions/{id}` endpoint, and
REM prints a short summary: the type, the folder, the pull sites and a few settings.
REM The path takes the subscription's id, so the script looks the id up by account,
REM application and folder first.
REM
REM Usage:
REM 06.subscriptions_id_GET.bat [ACCOUNT [APPLICATION [FOLDER]]]
REM
REM   ACCOUNT      the account that subscribes (default john)
REM   APPLICATION  the application it subscribes to (default AdvancedRoutingApplication)
REM   FOLDER       the folder of the subscription (default /inbox)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - Confirmed directly: an unknown id is a JSON 404, "Subscription with id X not found or not
REM   accessible.". `fields=` keeps the keys named, and always `type`. `type=`, which the
REM   reference says is needed to read a field of one subscription type, is not: `type=Basic` on an
REM   Advanced Routing subscription answers the whole subscription.
REM - The `type` of a subscription is the type of its application. A body that says another
REM   type is accepted, and the application's type is used. What else is there depends on it: an
REM   AdvancedRouting one has createFilesList, postClientDownloads, postProcessingActions and
REM   postTransmissionActions; Basic, SharedFolder, SiteMailbox and StandardRouter have
REM   postTransmissionActions; HumanSystem has `rules`; StandardRouter has `subscriberID`; MBFT has
REM   only the common fields. Every field that is not set is null, not absent.
REM - Confirmed directly: a subscription's folder is not made when the subscription is created. It
REM   is in the account's home folder after the account's next login, or after the first pull.
REM - PowerShell is used to read the id and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
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
SET SUBSCRIPTION_FILE=%TEMP%\subscription_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SUBSCRIPTION_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SUBSCRIPTION_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the subscription %SUBSCRIPTION_ID%.
    IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"
    EXIT /B 1
)
echo The subscription of %ACCOUNT% on %APPLICATION%, folder %FOLDER%, id %SUBSCRIPTION_ID%:
powershell -NoProfile -Command "$s = Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json; function v($x) { if ($null -eq $x -or $x -eq '') { '-' } else { [string]$x } }; $sites = @($s.transferConfigurations | Where-Object { $_.outbound -eq $false } | ForEach-Object { $_.site }); '  type:              ' + $s.type; '  retention (days):  ' + (v $s.fileRetentionPeriod); '  parallel pulls:    ' + (v $s.maxParallelSitPulls); '  pull sites:        ' + (v ($sites -join ', ')); '  flow attributes:   ' + @($s.flowAttributes.PSObject.Properties).Count"
IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"

echo.
echo Only some of its fields, with fields=id,folder,fileRetentionPeriod:
SET FIELDS_FILE=%TEMP%\subscription_fields_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%SUBSCRIPTION_ID%" --data-urlencode "fields=id,folder,fileRetentionPeriod" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%FIELDS_FILE%"
powershell -NoProfile -Command "Get-Content -Raw $env:FIELDS_FILE | ConvertFrom-Json | ConvertTo-Json -Compress"
IF EXIST "%FIELDS_FILE%" DEL "%FIELDS_FILE%"
