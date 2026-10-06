@echo off
REM ==============================================================================
REM Script Name: billable_GET_report.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Prints the number of billable transfers per day, for the last BT_REPORT_DAYS
REM days (today included), for each of the three accounts of this feature, side by
REM side, using the `/logs/transfers` endpoint and its `isBillable` filter:
REM
REM   partner_to_pull_from   the uploads of the sample files, and their pulls out
REM   the test account       the pulls in, and the pushes out
REM   partner_to_push_to     the pushes arriving
REM
REM Not numbered like the setup steps: 00.run_all.bat runs this one twice, once
REM before anything else and once at the end, to show the before/after change for
REM today, account by account.
REM
REM Usage:
REM billable_GET_report.bat [LABEL [ACCOUNT]]
REM
REM LABEL is printed in the heading (for example "before" or "after"); it does not
REM change what is measured. ACCOUNT reports on another test account than the
REM default (the same name given to 00.run_all.bat).
REM
REM Notes:
REM - Each account is filtered with account=, an exact match. Not accountName=:
REM   /logs/transfers ignores that without a word and counts every account on the
REM   server (confirmed directly). An earlier version of this script used it.
REM - The partners are shared by every test account, so their counts include any
REM   other test account's runs on the same day.
REM - Each day is a full calendar day, midnight to midnight, in RFC 2822, built
REM   with PowerShell, with English day names and a +0300 style offset.
REM - The count is resultSet.totalCount. resultSet.returnCount is capped by limit,
REM   which is 1 here to keep the response small.
REM - The last lines are TODAY_COUNT <account>: <count>, one per account, for
REM   00.run_all.bat to read.
REM - Uses PowerShell for the date arithmetic and to read the response.
REM ==============================================================================

SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
IF NOT "%~2"=="" (
    ECHO %~2| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
        echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~2
        EXIT /B 2
    )
    SET BT_RUN_ACCOUNT=%~2
)
CALL "%~dp0settings.bat"

SET REPORT_LABEL=%~1
IF "%REPORT_LABEL%"=="" SET REPORT_LABEL=report
SET RESPONSE_FILE=%TEMP%\bt_report_%RANDOM%.json

echo Billable transfers per day, last %BT_REPORT_DAYS% day(s) (%REPORT_LABEL%)
echo.
echo   day         %BT_PULL_PARTNER%  %BT_TEST_ACCOUNT%  %BT_PUSH_PARTNER%

SET /A LAST_OFFSET=%BT_REPORT_DAYS%-1
SET TODAY_1=
SET TODAY_2=
SET TODAY_3=
FOR /L %%D IN (%LAST_OFFSET%,-1,0) DO CALL :report_day %%D

REM Machine-readable lines, so 00.run_all.bat can diff today's counts before and
REM after, without re-parsing the table above
echo.
echo TODAY_COUNT %BT_PULL_PARTNER%: %TODAY_1%
echo TODAY_COUNT %BT_TEST_ACCOUNT%: %TODAY_2%
echo TODAY_COUNT %BT_PUSH_PARTNER%: %TODAY_3%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:report_day
SET DAY_OFFSET=%1

REM English day and month names whatever the Windows language, and the offset
REM as +0300, not the +03:00 .NET writes by default
FOR /F "tokens=1,2,3 delims=|" %%A IN ('powershell -NoProfile -Command "$c=[Globalization.CultureInfo]::InvariantCulture; $s=(Get-Date).Date.AddDays(-%DAY_OFFSET%); $e=$s.AddDays(1); '{0}|{1}|{2}' -f $s.ToString('yyyy-MM-dd'), ($s.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $s.ToString('zzz').Replace(':','')), ($e.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $e.ToString('zzz').Replace(':',''))"') DO (
    SET DAY_LABEL=%%A
    SET START_RFC=%%B
    SET END_RFC=%%C
)

CALL :billable_count "%BT_PULL_PARTNER%"
SET COUNT_1=%DAY_COUNT%
CALL :billable_count "%BT_TEST_ACCOUNT%"
SET COUNT_2=%DAY_COUNT%
CALL :billable_count "%BT_PUSH_PARTNER%"
SET COUNT_3=%DAY_COUNT%

echo   %DAY_LABEL%  %COUNT_1%  %COUNT_2%  %COUNT_3%
IF "%DAY_OFFSET%"=="0" (
    SET TODAY_1=%COUNT_1%
    SET TODAY_2=%COUNT_2%
    SET TODAY_3=%COUNT_3%
)
EXIT /B 0

REM billable_count ACCOUNT: sets DAY_COUNT, or ? when none could be read
:billable_count
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
  --data-urlencode "isBillable=true" --data-urlencode "account=%~1" ^
  --data-urlencode "startTimeAfter=%START_RFC%" --data-urlencode "endTimeBefore=%END_RFC%" ^
  --data-urlencode "limit=1" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" > "%RESPONSE_FILE%"
SET DAY_COUNT=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET DAY_COUNT=%%N
IF "%DAY_COUNT%"=="" SET DAY_COUNT=?
EXIT /B 0
