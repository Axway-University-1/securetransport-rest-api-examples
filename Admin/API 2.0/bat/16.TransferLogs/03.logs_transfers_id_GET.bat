@echo off
REM ==============================================================================
REM Script Name: 03.logs_transfers_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one transfer from the transfer log using the `/logs/transfers/{id}`
REM endpoint: its status, the file, who transferred it, over which protocol, and how long it took.
REM
REM Usage:
REM 03.logs_transfers_id_GET.bat [ID]
REM
REM   ID  the transfer's id, as 01.logs_transfers_GET.bat lists it under id.urlrepresentation
REM       (default: the newest transfer in the log)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The id is the urlrepresentation of the transfer's id object: Base64 of "Id
REM   [mTransferStatusId=..., mTransferStartTime=...]". An id in any other form answers 400
REM   "Invalid format for transfer ID".
REM - Confirmed directly: the fields of one transfer are not those of the list. The list has
REM   incoming, protocol and serverInitiated; one transfer has transferType, transferSite,
REM   userClass and duration, and fields=incoming answers 400 "Field incoming does not exist".
REM - isCancelable and isResubmittable tell whether the server will allow 04.logs_transfers_id_operations_POST.bat
REM   to cancel or resubmit this transfer now. Confirmed directly: a transfer in progress is never
REM   cancelable, over FTP, HTTP or SSH, whatever its size; a PeSIT pull that failed and is waiting
REM   to be retried is; a finished incoming transfer is resubmittable, a failed one is not.
REM - PowerShell is used to look the newest transfer up and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers
SET "TRANSFER_ID=%~1"
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
IF NOT "%TRANSFER_ID%"=="" GOTO have_id
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" --data-urlencode "sortByStartTime=descending" --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.result) { $r.result[0].id.urlrepresentation }"') DO SET "TRANSFER_ID=%%I"
IF "%TRANSFER_ID%"=="" (
    echo There are no transfers in the log.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
:have_id

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%TRANSFER_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the transfer ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; '  {0}: {1} ({2}), {3}' -f $r.status, $r.file, $r.transferType, $r.duration; '  account {0}, login {1}, server {2}, site {3}' -f (& $d $r.account), (& $d $r.login), (& $d $r.serverName), (& $d $r.transferSite); '  started ' + $r.startTime; $c = if ($r.isCancelable) { 'yes' } else { 'no' }; $s = if ($r.isResubmittable) { 'yes' } else { 'no' }; '  cancelable: ' + $c + ', resubmittable: ' + $s"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
