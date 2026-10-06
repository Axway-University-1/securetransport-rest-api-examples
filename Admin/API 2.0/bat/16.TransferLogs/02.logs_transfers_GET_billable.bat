@echo off
REM ==============================================================================
REM Script Name: 02.logs_transfers_GET_billable.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script counts the billable transfers per day, using the
REM `/logs/transfers` endpoint and its `isBillable` filter. It prints one line
REM per calendar day, today last, and the total.
REM
REM Usage:
REM 02.logs_transfers_GET_billable.bat [DAYS [ACCOUNT]]
REM
REM   DAYS     how many days to count, today included (default 7)
REM   ACCOUNT  count only this account's transfers (default: every account)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account is filtered with account=. The endpoint ignores accountName=
REM   without a word and answers for every account (confirmed directly).
REM - SecureTransport 5.5-20260924 or later. An earlier release, or a transfer
REM   from before the upgrade, has no billable status, and counts as 0.
REM - Each day runs from midnight to midnight in this machine's time zone, sent in
REM   RFC 2822, for example "Mon, 05 Oct 2026 00:00:00 +0300".
REM - The count is resultSet.totalCount. resultSet.returnCount is capped by limit,
REM   which is 1 here to keep the response small.
REM - Features\audit-billable-transfers explains which transfers are billable, and
REM   tests it.
REM - PowerShell is used for the dates and to read the response, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET DAYS=%~1
IF "%DAYS%"=="" SET DAYS=7
ECHO %DAYS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo DAYS must be a whole number, 1 or more: %DAYS%
    EXIT /B 2
)
SET ACCOUNT=%~2
SET RESPONSE_FILE=%TEMP%\billable_%RANDOM%.json

IF "%ACCOUNT%"=="" (
    echo Billable transfers per day, for every account
) ELSE (
    echo Billable transfers per day, for %ACCOUNT%
)

SET TOTAL=0
SET /A LAST_OFFSET=%DAYS%-1
FOR /L %%D IN (%LAST_OFFSET%,-1,0) DO CALL :count_day %%D

echo Total: %TOTAL% billable transfer(s) in %DAYS% day(s)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:count_day
SET DAY_OFFSET=%1
REM English day and month names whatever the Windows language, and the offset
REM as +0300, not the +03:00 .NET writes by default
FOR /F "tokens=1,2,3 delims=|" %%A IN ('powershell -NoProfile -Command "$c=[Globalization.CultureInfo]::InvariantCulture; $s=(Get-Date).Date.AddDays(-%DAY_OFFSET%); $e=$s.AddDays(1); '{0}|{1}|{2}' -f $s.ToString('yyyy-MM-dd'), ($s.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $s.ToString('zzz').Replace(':','')), ($e.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $e.ToString('zzz').Replace(':',''))"') DO (
    SET DAY_LABEL=%%A
    SET START_RFC=%%B
    SET END_RFC=%%C
)

REM Only add the account to the query when one was given
IF "%ACCOUNT%"=="" (
    curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
      --data-urlencode "isBillable=true" ^
      --data-urlencode "startTimeAfter=%START_RFC%" --data-urlencode "endTimeBefore=%END_RFC%" ^
      --data-urlencode "limit=1" --data-urlencode "fields=id" ^
      -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
) ELSE (
    curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
      --data-urlencode "isBillable=true" --data-urlencode "account=%ACCOUNT%" ^
      --data-urlencode "startTimeAfter=%START_RFC%" --data-urlencode "endTimeBefore=%END_RFC%" ^
      --data-urlencode "limit=1" --data-urlencode "fields=id" ^
      -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
)

SET DAY_COUNT=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET DAY_COUNT=%%N

IF "%DAY_COUNT%"=="" (
    echo   %DAY_LABEL%  could not read a count
    EXIT /B 0
)
echo   %DAY_LABEL%  %DAY_COUNT%
SET /A TOTAL=%TOTAL%+%DAY_COUNT%
EXIT /B 0
