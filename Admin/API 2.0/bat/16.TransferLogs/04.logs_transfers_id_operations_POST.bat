@echo off
REM ==============================================================================
REM Script Name: 04.logs_transfers_id_operations_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs an operation on one transfer using the
REM `/logs/transfers/{id}/operations` endpoint: cancel it, resubmit it, verify its receipt, or
REM acknowledge it.
REM
REM Usage:
REM 04.logs_transfers_id_operations_POST.bat ID OPERATION [MESSAGE]
REM
REM   ID         the transfer's id (see 03.logs_transfers_id_GET.bat)
REM   OPERATION  cancel, resubmit, verify, ack or nack
REM   MESSAGE    for ack and nack only: the message to send (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The id is required: these operations act on a real transfer.
REM - Confirmed directly, on a transfer that had finished: resubmit answers 200 "was
REM   successfully resubmitted". cancel answers 400 "is not eligible for cancellation"; verify
REM   400 "does not have a receipts"; ack and nack 400 "protocol http does not support
REM   acknowledgements", since only a received PeSIT transfer can be acknowledged.
REM - Confirmed directly: cancel is refused for a transfer that is still In Progress: a 10 MB upload
REM   over FTP, a 10 MB upload through the EndUser API, a 10 MB pull over SSH, each kept running
REM   for 40 seconds, and a route's send to a partner; resubmit then answers 400 "cannot be
REM   resubmitted". The server says so itself: isCancelable is false (03.logs_transfers_id_GET.bat).
REM - Confirmed directly: what can be cancelled is a transfer waiting to be retried: a PeSIT pull
REM   that failed (the sender had no such file) and is counted as "to retry" by
REM   05.logs_transfers_pullSummary_GET.bat. Cancel answers 200 "was successfully cancelled", the
REM   count moves from retry to failed, isCancelable turns false, and a second cancel is refused.
REM   Check 48 shows both.
REM - Confirmed directly: any other operation answers 403 with a message about a configuration
REM   error. This script sends only the five.
REM - The message goes in the body as {"userMessage": ...}, and only for ack and nack; it can
REM   use Expression Language.
REM - PowerShell is used to build the body and print the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers
SET "TRANSFER_ID=%~1"
SET "OPERATION=%~2"
SET "MESSAGE=%~3"
IF "%TRANSFER_ID%"=="" GOTO usage
IF "%OPERATION%"=="cancel" GOTO op_ok
IF "%OPERATION%"=="resubmit" GOTO op_ok
IF "%OPERATION%"=="verify" GOTO op_ok
IF "%OPERATION%"=="ack" GOTO op_ok
IF "%OPERATION%"=="nack" GOTO op_ok
:usage
echo Usage: 04.logs_transfers_id_operations_POST.bat ID cancel^|resubmit^|verify^|ack^|nack [MESSAGE]
EXIT /B 2
:op_ok
SET BODY_FILE=%TEMP%\logs_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
SET EXTRA=
IF "%MESSAGE%"=="" GOTO send
IF "%OPERATION%"=="ack" GOTO with_message
IF "%OPERATION%"=="nack" GOTO with_message
GOTO send
:with_message
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (@{ userMessage = $env:MESSAGE } | ConvertTo-Json -Compress))"
SET EXTRA= -H "Content-Type: application/json" -d "@%BODY_FILE%"
:send

echo Performing %OPERATION%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%TRANSFER_ID%/operations?operation=%OPERATION%" -H "accept: application/json" -H "%REFERER_HEADER%"%EXTRA%') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } else { Get-Content -Raw $env:RESPONSE_FILE } } catch { Get-Content -Raw $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="200" EXIT /B 1
