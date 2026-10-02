@echo off
REM ==============================================================================
REM Script Name: billable_GET_report.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Prints the number of billable transfers per day, for the last BT_REPORT_DAYS
REM days (today included), for this feature's test account, using the
REM `/logs/transfers` endpoint and its `isBillable` filter.
REM
REM Not numbered like the setup steps: 00.run_all.bat runs this one twice, once
REM before anything else and once at the end, to show the before/after change for
REM today.
REM
REM Usage:
REM billable_GET_report.bat [LABEL]
REM
REM LABEL is printed in the heading (for example "before" or "after"); it does not
REM change what is measured.
REM
REM Notes:
REM - Scoped to accountName=BT_TEST_ACCOUNT, so an existing account with the same
REM   name on your server does not throw the count off. Run this against a server
REM   that does not already have that account, for a clean baseline.
REM - Each day is a full calendar day, midnight to midnight, in RFC 2822, built
REM   with PowerShell's own date formatting.
REM - Uses PowerShell for the date arithmetic and to read the response.
REM - Confirmed directly: /logs/transfers' resultSet carries TWO counts, not one -
REM   returnCount (how many rows are in THIS page, capped by limit) and
REM   totalCount (the true total matching the filter, independent of limit). Most
REM   other list endpoints in this API only need returnCount, since their
REM   returnCount already ignores limit; this one does not. Reading returnCount
REM   here, with limit=1 set to keep the response small, silently capped every
REM   day's count at 1 - confirmed directly, a real bug caught by comparing
REM   against File Tracking's own count for the same account and day.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET REPORT_LABEL=%~1
IF "%REPORT_LABEL%"=="" SET REPORT_LABEL=report

echo Billable transfers per day, last %BT_REPORT_DAYS% day(s), for %BT_TEST_ACCOUNT% (%REPORT_LABEL%)

SET /A LAST_OFFSET=%BT_REPORT_DAYS%-1
SET TODAY_COUNT=
FOR /L %%D IN (%LAST_OFFSET%,-1,0) DO CALL :report_day %%D

REM A machine-readable line, so 00.run_all.bat can diff today's count before and
REM after, without re-parsing the printed table above
echo TODAY_COUNT: %TODAY_COUNT%
EXIT /B 0

:report_day
SET DAY_OFFSET=%1
SET RESPONSE_FILE=%TEMP%\bt_report_%RANDOM%.json

FOR /F "tokens=1,2,3 delims=|" %%A IN ('powershell -NoProfile -Command "$s=(Get-Date).Date.AddDays(-%DAY_OFFSET%); $e=$s.AddDays(1); '('{0}|{1}|{2}' -f $s.ToString('yyyy-MM-dd'), $s.ToString('ddd, dd MMM yyyy HH:mm:ss zzz'), $e.ToString('ddd, dd MMM yyyy HH:mm:ss zzz'))"') DO (
    SET DAY_LABEL=%%A
    SET START_RFC=%%B
    SET END_RFC=%%C
)

curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
  --data-urlencode "isBillable=true" --data-urlencode "accountName=%BT_TEST_ACCOUNT%" ^
  --data-urlencode "startTimeAfter=%START_RFC%" --data-urlencode "endTimeBefore=%END_RFC%" ^
  --data-urlencode "limit=1" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" > "%RESPONSE_FILE%"

SET DAY_COUNT=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET DAY_COUNT=%%N

IF NOT DEFINED DAY_COUNT (
    echo   %DAY_LABEL%  could not read a count. The response was:
    TYPE "%RESPONSE_FILE%"
) ELSE (
    echo   %DAY_LABEL%  %DAY_COUNT% billable transfer^(s^)
    IF "%DAY_OFFSET%"=="0" SET TODAY_COUNT=%DAY_COUNT%
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
