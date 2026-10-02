@echo off
REM ==============================================================================
REM Script Name: 00.run_all.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Runs the whole test, start to finish:
REM
REM   1. Prints today's billable transfer count, and the six days before it
REM      (billable_GET_report.bat "before").
REM   2. Sets up the account, the sites, the folders, the application, the
REM      routes and the subscriptions (01 to 09), uploads the sample files and
REM      the two archives (10), and runs the six pulls (11).
REM   3. Prints the same report again (billable_GET_report.bat "after"), so
REM      today's count can be compared against step 1.
REM   4. Prints the real before/after delta for today - how many billable
REM      transfers this run actually added - and restates the rule. It does not
REM      print a fixed per-scenario table: see the Notes below for why.
REM
REM Usage:
REM 00.run_all.bat              steps 1 to 4, leaves everything in place
REM 00.run_all.bat --cleanup    the same, then removes everything (99)
REM
REM Notes:
REM - It stops at the first setup step that fails: a non-zero exit, or a line
REM   starting HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing
REM   is cleaned up, so you can look.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Step 4 used to print a fixed table of the billable count the rule predicts
REM   per scenario. That table was wrong, and is gone: billing here is tracked
REM   per transfer chain (coreId), not per filename, and step 10's own upload (a
REM   real, billable Inbound in its own right) and the pull that empties the drop
REM   folder (that chain's own free first outbound) are each a SEPARATE chain from
REM   the scenario's intended pull/push, adding billable transfers the rule's
REM   plain six-scenario description never counted. Confirmed directly, by
REM   comparing this run's own File Tracking entries by coreId. Read the actual
REM   result in File Tracking, grouped by Transfer name, rather than trusting a
REM   static prediction.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET CLEANUP=0
IF "%~1"=="--cleanup" SET CLEANUP=1
IF NOT "%~1"=="" IF NOT "%~1"=="--cleanup" (
    echo Usage: 00.run_all.bat [--cleanup]
    EXIT /B 2
)

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

echo.
echo === Step 1: billable transfers before this run ===
SET REPORT_LOG=%TEMP%\bt_report_%RANDOM%.log
CALL "%~dp0billable_GET_report.bat" before > "%REPORT_LOG%"
TYPE "%REPORT_LOG%"
SET BEFORE_TODAY=
FOR /F "tokens=2 delims=: " %%T IN ('FINDSTR /B "TODAY_COUNT:" "%REPORT_LOG%"') DO SET BEFORE_TODAY=%%T
IF EXIST "%REPORT_LOG%" DEL "%REPORT_LOG%"

REM Every numbered setup step, except this script and the cleanup
SET TOTAL=0
FOR %%S IN ("%~dp0??.*.bat") DO CALL :count %%~nxS

echo.
echo === Step 2: perform the transfers ===
SET N=0
FOR %%S IN ("%~dp0??.*.bat") DO CALL :run_step %%~nxS
IF DEFINED STEP_FAILED EXIT /B 1

CALL "%~dp012.files_GET_result.bat"

echo.
echo === Step 3: billable transfers after this run ===
SET REPORT_LOG=%TEMP%\bt_report_%RANDOM%.log
CALL "%~dp0billable_GET_report.bat" after > "%REPORT_LOG%"
TYPE "%REPORT_LOG%"
SET AFTER_TODAY=
FOR /F "tokens=2 delims=: " %%T IN ('FINDSTR /B "TODAY_COUNT:" "%REPORT_LOG%"') DO SET AFTER_TODAY=%%T
IF EXIST "%REPORT_LOG%" DEL "%REPORT_LOG%"

echo.
echo === Step 4: analysis ===
IF DEFINED BEFORE_TODAY IF DEFINED AFTER_TODAY CALL :print_delta
IF NOT DEFINED BEFORE_TODAY echo Could not read today's count from step 1 above; see it for the raw response.
IF NOT DEFINED AFTER_TODAY echo Could not read today's count from step 3 above; see it for the raw response.
echo.
echo The rule, from the Admin Guide: every inbound transfer is billable. For a
echo given file, the first outbound transfer that follows it is not billable;
echo every outbound transfer after that first one is.
echo.
echo That rule is tracked per transfer chain (coreId), not per filename. Step 10's
echo own upload into outbound-drop is a real, billable Inbound transfer in its own
echo right, and the pull that later empties outbound-drop is THAT chain's own free
echo first outbound - both separate from, and in addition to, the scenario's
echo intended pull into subscription/sN and push to a partner. For the exact
echo breakdown, read File Tracking for %BT_TEST_ACCOUNT%, grouped by Transfer name.

IF "%CLEANUP%"=="1" (
    echo.
    echo === Cleanup: 99.cleanup_DELETE.bat ===
    CALL "%~dp099.cleanup_DELETE.bat"
) ELSE (
    echo.
    echo Run 99.cleanup_DELETE.bat to remove everything this created.
)
EXIT /B 0

:count
SET NAME=%1
IF "%NAME:~0,2%"=="00" EXIT /B 0
IF "%NAME:~0,2%"=="99" EXIT /B 0
SET /A TOTAL=%TOTAL%+1
EXIT /B 0

:run_step
IF DEFINED STEP_FAILED EXIT /B 1
SET NAME=%1
IF "%NAME:~0,2%"=="00" EXIT /B 0
IF "%NAME:~0,2%"=="99" EXIT /B 0
SET /A N=%N%+1
echo.
echo --- %N% of %TOTAL%: %NAME% ---
SET LOG=%TEMP%\bt_run_%RANDOM%.log
CALL "%~dp0%NAME%" > "%LOG%" 2>&1
SET STEP_RC=%ERRORLEVEL%
TYPE "%LOG%"
SET LOG_HAS_ERROR=
FINDSTR /R /C:"^HTTP [45][0-9][0-9]" "%LOG%" >NUL && SET LOG_HAS_ERROR=1
IF EXIST "%LOG%" DEL "%LOG%"
IF NOT "%STEP_RC%"=="0" SET LOG_HAS_ERROR=1
IF DEFINED LOG_HAS_ERROR (
    echo.
    echo Stopped at step %N% of %TOTAL%: %NAME% failed.
    echo Nothing after it was run, and nothing was cleaned up.
    echo Fix it, run 99.cleanup_DELETE.bat, and start again.
    SET STEP_FAILED=1
    EXIT /B 1
)
REM The pull (11) triggers routes and pushes that run asynchronously
IF "%NAME:~0,2%"=="11" CALL :pause_steps
EXIT /B 0

:pause_steps
SET /A PING_COUNT=%BT_STEP_PAUSE_SECONDS%+1
echo.
echo Pausing %BT_STEP_PAUSE_SECONDS% seconds...
ping -n %PING_COUNT% 127.0.0.1 >NUL
EXIT /B 0

:print_delta
echo Today's billable count for %BT_TEST_ACCOUNT%: %BEFORE_TODAY% before this run, %AFTER_TODAY% after.
SET /A DELTA=%AFTER_TODAY%-%BEFORE_TODAY%
echo This run added %DELTA% billable transfer^(s^) today.
EXIT /B 0
