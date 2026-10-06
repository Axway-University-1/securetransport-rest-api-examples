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
REM   1. Prints the billable transfer count per day of the three accounts, today
REM      and the six days before it (billable_GET_report.bat "before").
REM   2. Sets up the three accounts, the sites, the folders, the application, the
REM      routes and the subscriptions (01 to 09), uploads the sample files and
REM      the two archives to partner_to_pull_from (10), and runs the six pulls
REM      (11).
REM   3. Prints the same report again (billable_GET_report.bat "after").
REM   4. For each account, prints how many billable transfers this run added
REM      today, next to what the rule predicts for it, and whether they match.
REM
REM Usage:
REM 00.run_all.bat [ACCOUNT [INBOUND_ONLY [IN_AND_OUT]]] [--cleanup]
REM
REM   ACCOUNT        the test account to create and use (default btTestAccount).
REM                  Every other object name is derived from it.
REM   INBOUND_ONLY   how many files scenario 2.1 (inbound only) runs (default 1)
REM   IN_AND_OUT     how many files scenario 2.2 (inbound, then one outbound)
REM                  runs (default 1)
REM   --cleanup      after step 4, remove everything again (99)
REM
REM For example:
REM 00.run_all.bat                          defaults, leaves everything in place
REM 00.run_all.bat test_account             a test account named test_account
REM 00.run_all.bat test_account 6 12        and 6 inbound only, 12 in and out
REM 00.run_all.bat test_account 6 12 --cleanup
REM
REM Notes:
REM - It stops at the first setup step that fails: a non-zero exit, or a line
REM   starting HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing
REM   is cleaned up, so you can look.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - The partners are shared by every test account. A run of another test
REM   account on the same day, at the same time, adds to their counts too.
REM ==============================================================================

REM Everything this sets, including the arguments below, ends with this script,
REM so a later run in the same console starts from the defaults again
SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0

SET CLEANUP=0
SET BT_RUN_ACCOUNT=
SET BT_RUN_INBOUND_ONLY=
SET BT_RUN_IN_AND_OUT=
SET ARG_N=0
SET ARG_ERROR=
:parse_args
IF "%~1"=="" GOTO :args_done
CALL :take_arg "%~1"
REM SHIFT /1 leaves %0 alone, so %~dp0 still points at this script's folder
SHIFT /1
GOTO :parse_args
:args_done
IF DEFINED ARG_ERROR (
    echo Usage: 00.run_all.bat [ACCOUNT [INBOUND_ONLY [IN_AND_OUT]]] [--cleanup]
    EXIT /B 2
)

REM Loaded after the arguments, so settings.bat applies them, and every step this
REM runs inherits them
CALL "%~dp0settings.bat"

echo Account %BT_TEST_ACCOUNT%: scenario 2.1 with %BT_INBOUND_ONLY_COUNT% file^(s^), scenario 2.2 with %BT_IN_AND_OUT_COUNT% file^(s^).

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

echo.
echo === Step 1: billable transfers before this run ===
SET REPORT_LOG=%TEMP%\bt_report_%RANDOM%.log
CALL "%~dp0billable_GET_report.bat" before > "%REPORT_LOG%"
TYPE "%REPORT_LOG%"
CALL :today_count "%BT_PULL_PARTNER%" BEFORE_PULL
CALL :today_count "%BT_TEST_ACCOUNT%" BEFORE_TEST
CALL :today_count "%BT_PUSH_PARTNER%" BEFORE_PUSH
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
CALL :today_count "%BT_PULL_PARTNER%" AFTER_PULL
CALL :today_count "%BT_TEST_ACCOUNT%" AFTER_TEST
CALL :today_count "%BT_PUSH_PARTNER%" AFTER_PUSH
IF EXIST "%REPORT_LOG%" DEL "%REPORT_LOG%"

REM What the rule predicts each account adds. FILES is every file pulled: the
REM inbound-only and in-and-out files, 1 for 2.3, 2 for 2.4, and one archive each
REM for 2.5 and 2.6.
REM   partner_to_pull_from: each upload in is billable; each pull out is the
REM     file's first outbound, so free
REM   the test account: each pull in is billable; of the pushes out, the first in
REM     each transfer chain (coreId) is free and the rest are billable. Decompress
REM     keeps the archive's chain and Compress starts a new one (confirmed on a
REM     real run), so: 2.3 one billable push, 2.5 one, 2.6 three of its four
REM   partner_to_push_to: each push arriving is billable. 2.2 one per file, 2.3
REM     two, 2.4 one archive, 2.5 two files, 2.6 two files to each of two folders
SET /A FILES=%BT_INBOUND_ONLY_COUNT%+%BT_IN_AND_OUT_COUNT%+5
SET /A PREDICT_PULL=%FILES%
SET /A PREDICT_TEST=%FILES%+5
SET /A PREDICT_PUSH=%BT_IN_AND_OUT_COUNT%+9

echo.
echo === Step 4: analysis ===
echo The rule, from the Admin Guide: every inbound transfer is billable. For a
echo given file, the first outbound transfer that follows it is not billable;
echo every outbound transfer after that first one is.
echo.
echo Billable transfers this run added today, by account:
echo.
echo   account  before  after  added  the rule predicts
SET MATCHED=1
CALL :analysis_row "%BT_PULL_PARTNER%" "%BEFORE_PULL%" "%AFTER_PULL%" %PREDICT_PULL%
CALL :analysis_row "%BT_TEST_ACCOUNT%" "%BEFORE_TEST%" "%AFTER_TEST%" %PREDICT_TEST%
CALL :analysis_row "%BT_PUSH_PARTNER%" "%BEFORE_PUSH%" "%AFTER_PUSH%" %PREDICT_PUSH%
echo.
IF "%MATCHED%"=="1" (
    echo Every account added what the rule predicts.
) ELSE (
    echo An account did not add what the rule predicts, or its count could not be
    echo read. Read File Tracking for that account, grouped by Transfer name. A push
    echo still under way when step 3 ran shows up there, and in a later report.
)

IF "%CLEANUP%"=="1" (
    echo.
    echo === Cleanup: 99.cleanup_DELETE.bat ===
    CALL "%~dp099.cleanup_DELETE.bat"
) ELSE (
    echo.
    echo Run 99.cleanup_DELETE.bat %BT_TEST_ACCOUNT% to remove everything this created.
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

REM today_count ACCOUNT VARIABLE: the TODAY_COUNT the report printed for an account
:today_count
SET %2=
FOR /F "tokens=3 delims=: " %%T IN ('FINDSTR /B /C:"TODAY_COUNT %~1:" "%REPORT_LOG%"') DO SET %2=%%T
EXIT /B 0

REM analysis_row ACCOUNT BEFORE AFTER PREDICTED
:analysis_row
SET ROW_BEFORE=%~2
SET ROW_AFTER=%~3
IF "%ROW_BEFORE%"=="" SET ROW_BEFORE=?
IF "%ROW_AFTER%"=="" SET ROW_AFTER=?
IF "%ROW_BEFORE%"=="?" GOTO :analysis_unknown
IF "%ROW_AFTER%"=="?" GOTO :analysis_unknown
SET /A ROW_ADDED=%ROW_AFTER%-%ROW_BEFORE%
SET ROW_NOTE=
IF NOT "%ROW_ADDED%"=="%4" (
    SET ROW_NOTE=   differs
    SET MATCHED=0
)
echo   %~1  %ROW_BEFORE%  %ROW_AFTER%  %ROW_ADDED%  %4%ROW_NOTE%
EXIT /B 0
:analysis_unknown
SET MATCHED=0
echo   %~1  %ROW_BEFORE%  %ROW_AFTER%  ?  %4
EXIT /B 0

:take_arg
IF "%~1"=="--cleanup" (
    SET CLEANUP=1
    EXIT /B 0
)
SET ARG_VALUE=%~1
IF "%ARG_VALUE:~0,1%"=="-" (
    SET ARG_ERROR=1
    EXIT /B 0
)
SET /A ARG_N=%ARG_N%+1
IF %ARG_N%==1 CALL :check_account "%ARG_VALUE%"
IF %ARG_N%==2 CALL :check_count "%ARG_VALUE%" BT_RUN_INBOUND_ONLY
IF %ARG_N%==3 CALL :check_count "%ARG_VALUE%" BT_RUN_IN_AND_OUT
IF %ARG_N% GTR 3 SET ARG_ERROR=1
EXIT /B 0

:check_account
ECHO %~1| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
    echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~1
    SET ARG_ERROR=1
    EXIT /B 0
)
SET BT_RUN_ACCOUNT=%~1
EXIT /B 0

:check_count
ECHO %~1| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo INBOUND_ONLY and IN_AND_OUT must be whole numbers, 1 or more: %~1
    SET ARG_ERROR=1
    EXIT /B 0
)
SET %~2=%~1
EXIT /B 0
