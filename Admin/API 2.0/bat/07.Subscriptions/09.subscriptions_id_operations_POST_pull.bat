@echo off
REM ==============================================================================
REM Script Name: 09.subscriptions_id_operations_POST_pull.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script pulls files into a subscription's folder on demand, using the
REM `/subscriptions/{id}/operations` endpoint with operation=Pull. The pull uses a
REM transfer site of the subscription; the files it matches are downloaded into the
REM subscription's folder, where the routes of the subscription see them.
REM
REM Usage:
REM 09.subscriptions_id_operations_POST_pull.bat ACCOUNT APPLICATION FOLDER [SITE]
REM
REM   ACCOUNT      the account that subscribes
REM   APPLICATION  the application it subscribes to
REM   FOLDER       the folder of the subscription
REM   SITE         the transfer site to pull with (default: the site of the subscription's
REM                own PARTNER-IN transfer configuration)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The subscription is looked up by account, application and folder, and must be the only one
REM   that matches. A subscription is addressed by a generated id, and an account may have several
REM   on one application as long as their folders differ.
REM - 02.subscriptions_POST.bat creates a subscription with a pull site. The site is read from the
REM   subscription, so the subscription must have a transfer configuration, or SITE must be given.
REM - The pull runs on in the background: 202 means it was accepted. The script prints the
REM   operationIndex of the answer's link; follow it with 16.TransferLogs/01.logs_transfers_GET.bat.
REM - Confirmed directly: a file pulled lands in the subscription's folder within seconds and stays on
REM   the partner (the pull copies). The body is needed: with none the answer is a 403 "The server was
REM   unable to comply with your request"; `{"type":"pull"}` on a subscription with no transfer
REM   configuration is 400 "No transfer configuration found for this subscription."; a site that does
REM   not exist is 406 "Site 'X' was not found."; a wrong `type` is 400 with a misleading
REM   "Unsupported parameter - site". `fileRetentionPeriod` (0 to 36500, else 400) in the body is the
REM   retention for this pull. When the subscription keeps a pull history (its fileRetentionPeriod is
REM   more than 0, which needs an SFTP site), a file already pulled is not pulled again, even after it
REM   was deleted from the folder, until 10.subscriptions_id_operations_POST_clearPullHistory.bat.
REM   `createFilesListEnabled` and `createFilesListFilename` in the body make this pull write a file
REM   that lists the files it pulled. The operation name is case sensitive (`pull` is 404).
REM - PowerShell is used to read the id and the site, and build the request body, in place of jq.
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
SET SITE=%~4
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
IF "%SITE%"=="" (
    FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "$s = Get-Content -Raw $env:SUBSCRIPTION_FILE | ConvertFrom-Json; @($s.transferConfigurations | Where-Object { $_.outbound -eq $false } | ForEach-Object { $_.site })[0]"') DO SET SITE=%%S
)
IF EXIST "%SUBSCRIPTION_FILE%" DEL "%SUBSCRIPTION_FILE%"
IF "%SITE%"=="" (
    echo The subscription has no pull site ^(no PARTNER-IN transfer configuration^); give one as the fourth argument.
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\subscription_pull_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\subscription_pull_answer_%RANDOM%.json
powershell -NoProfile -Command "[ordered]@{ type = 'pull'; site = $env:SITE } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Pulling into the folder '%FOLDER%' of '%ACCOUNT%' with the site '%SITE%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%SUBSCRIPTION_ID%/operations?operation=Pull" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="202" (
    powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.message; if ($r.link -match 'operationIndex=([^&]+)') { 'operationIndex: ' + $Matches[1] }"
) ELSE (
    type "%RESPONSE_FILE%"
)
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="202" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 09.subscriptions_id_operations_POST_pull.bat ACCOUNT APPLICATION FOLDER [SITE]
EXIT /B 2
