@echo off
REM ==============================================================================
REM Script Name: 05.logs_transfers_pullSummary_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the status summary of a pull using the
REM `/logs/transfers/pullSummary/{operationIndex}` endpoint: how many of the files it found were
REM pulled, failed, are being retried, are in progress or on hold.
REM
REM Usage:
REM 05.logs_transfers_pullSummary_GET.bat OPERATION_INDEX
REM
REM   OPERATION_INDEX  the pull's index, from the link in the 202 answer of
REM                    15.Transfers/01.transfers_operations_POST_pull.bat (operationIndex=...)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The summary counts the files the pull found, not the pull itself: a pull that found nothing,
REM   or could not connect, shows all zeros.
REM - Confirmed directly: an index nobody used is not an error: it answers 200 with every count
REM   0. Two pulls with one index add up.
REM - Confirmed directly: of the transfers a pull leaves in the log, only the one the pull itself
REM   started carries the operationIndex; the others show (none).
REM - "to retry" are pulls that failed and will be tried again: those are the ones
REM   04.logs_transfers_id_operations_POST.bat can cancel, after which they count as failed.
REM - PowerShell is used to print the counts, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers
SET "OPERATION_INDEX=%~1"
IF "%OPERATION_INDEX%"=="" (
    echo Usage: 05.logs_transfers_pullSummary_GET.bat OPERATION_INDEX
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:OPERATION_INDEX)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/pullSummary/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the summary ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0} file(s): {1} pulled, {2} failed, {3} to retry, {4} in progress, {5} on hold' -f $r.totalCount, $r.successful, $r.failed, $r.inRetry, $r.inProgress, $r.onHold"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
