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
REM   ACCOUNT      the account that subscribes (default john, or ST_EXAMPLE_ACCOUNT)
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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\subscription_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/subscriptions
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET APPLICATION=%~2
IF "%APPLICATION%"=="" SET APPLICATION=AdvancedRoutingApplication
SET FOLDER=%~3
IF "%FOLDER%"=="" SET FOLDER=/inbox
IF NOT "%~4"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "account=%ACCOUNT%" --data-urlencode "application=%APPLICATION%" --data-urlencode "fields=id,application,folder"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET SUBSCRIPTION_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.application -ceq $env:APPLICATION -and $_.folder -ceq $env:FOLDER }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SUBSCRIPTION_ID=%%B
)
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% subscriptions of the account %ACCOUNT% on the application %APPLICATION% and the folder %FOLDER%; this script acts on exactly one.
    EXIT /B 1
)
SET "URL=%MAIN_URL%/%SUBSCRIPTION_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the subscription %SUBSCRIPTION_ID%.
    EXIT /B 1
)
echo The subscription of %ACCOUNT% on %APPLICATION%, folder %FOLDER%, id %SUBSCRIPTION_ID%:
powershell -NoProfile -Command "$s = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; function v($x) { if ($null -eq $x -or $x -eq '') { '-' } else { [string]$x } }; $sites = @($s.transferConfigurations | Where-Object { $_.outbound -eq $false } | ForEach-Object { $_.site }); '  type:              ' + $s.type; '  retention (days):  ' + (v $s.fileRetentionPeriod); '  parallel pulls:    ' + (v $s.maxParallelSitPulls); '  pull sites:        ' + (v ($sites -join ', ')); '  flow attributes:   ' + @($s.flowAttributes.PSObject.Properties).Count"

echo.
echo Only some of its fields, with fields=id,folder,fileRetentionPeriod:
SET "URL=%MAIN_URL%/%SUBSCRIPTION_ID%"
SET CURL_OPTS=-G --data-urlencode "fields=id,folder,fileRetentionPeriod"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json | ConvertTo-Json -Compress"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 06.subscriptions_id_GET.bat [ACCOUNT [APPLICATION [FOLDER]]]
EXIT /B 2
