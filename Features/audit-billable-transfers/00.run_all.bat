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
REM Risk: write
REM
REM Notes:
REM - It stops at the first setup step that fails: a non-zero exit, or a line
REM   starting HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing
REM   is cleaned up, so you can look.
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - A stale home folder: an account's home folder stays on disk, with its owner,
REM   when the account is deleted, and a new account with another uid cannot
REM   create a folder directly in it (a 403 in step 04). So, only when no account
REM   name was chosen (no ACCOUNT, no BT_RUN_ACCOUNT, no BT_TEST_ACCOUNT in
REM   settings.local.bat), the run checks right after step 01 that the test account
REM   can create a folder directly in its home (bt_home_probe, made and removed
REM   again). If not, it deletes that test account only (never a partner), and
REM   moves to the next free name: <default>_2, _3, up to _9. It stops after _9.
REM   The report, --cleanup and the cleanup hint use the name it ended on.
REM   A name you chose is never changed: step 04 then fails, with a hint.
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

REM Was an account name given on the command line or in the environment?
SET ACCOUNT_CHOSEN=0
IF DEFINED BT_RUN_ACCOUNT SET ACCOUNT_CHOSEN=1

REM Loaded after the arguments, so settings.bat applies them, and every step this
REM runs inherits them
CALL "%~dp0settings.bat"

REM Or in settings.local.bat? Then it is never changed.
IF NOT "%BT_TEST_ACCOUNT%"=="%BT_DEFAULT_ACCOUNT%" SET ACCOUNT_CHOSEN=1

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
CALL :run_one "%NAME%"
IF DEFINED STEP_FAILED EXIT /B 1
REM The accounts exist now: is the test account's home folder usable?
IF "%NAME:~0,2%"=="01" CALL :ensure_usable_home
IF DEFINED STEP_FAILED EXIT /B 1
REM The pull (11) triggers routes and pushes that run asynchronously
IF "%NAME:~0,2%"=="11" CALL :pause_steps
EXIT /B 0

REM run_one FILE: runs one setup step, and sets STEP_FAILED when it fails
:run_one
SET LOG=%TEMP%\bt_run_%RANDOM%.log
CALL "%~dp0%~1" > "%LOG%" 2>&1
SET STEP_RC=%ERRORLEVEL%
TYPE "%LOG%"
SET LOG_HAS_ERROR=
FINDSTR /R /C:"^HTTP [45][0-9][0-9]" "%LOG%" >NUL && SET LOG_HAS_ERROR=1
IF EXIST "%LOG%" DEL "%LOG%"
IF NOT "%STEP_RC%"=="0" SET LOG_HAS_ERROR=1
IF DEFINED LOG_HAS_ERROR (
    echo.
    echo Stopped at step %N% of %TOTAL%: %~1 failed.
    echo Nothing after it was run, and nothing was cleaned up.
    echo Fix it, run 99.cleanup_DELETE.bat %BT_TEST_ACCOUNT%, and start again.
    SET STEP_FAILED=1
    EXIT /B 1
)
EXIT /B 0

REM home_probe: can the test account create a folder directly in its home? Makes
REM the folder bt_home_probe and removes it again. Sets PROBE_RC: 0 yes, 1 the home
REM is stale (a 403 "Error occurred while creating file"), 2 could not tell (the
REM login failed, or another error), which 04 then reports as it always did.
:home_probe
SET PROBE_RC=2
SET EU_ACCOUNT=%BT_TEST_ACCOUNT%
CALL "%~dp0..\lib\enduser.bat" login >NUL
IF ERRORLEVEL 1 EXIT /B 0
SET PROBE_BODY=%TEMP%\bt_probe_%RANDOM%.json
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%PROBE_BODY%"
CALL "%~dp0..\lib\enduser.bat" call POST "files/bt_home_probe" "application/json" "%PROBE_BODY%"
IF EXIST "%PROBE_BODY%" DEL "%PROBE_BODY%"
SET PROBE_CODE=%EU_CODE%
IF "%PROBE_CODE:~0,1%"=="2" SET PROBE_RC=0
IF "%PROBE_CODE:~0,1%"=="2" CALL "%~dp0..\lib\enduser.bat" call DELETE "files/bt_home_probe" ""
IF "%PROBE_CODE%"=="403" FINDSTR /C:"Error occurred while creating file" "%EU_BODY_FILE%" >NUL && SET PROBE_RC=1
CALL "%~dp0..\lib\enduser.bat" logout >NUL
EXIT /B 0

REM ensure_usable_home: after step 01. Only when no account name was chosen.
:ensure_usable_home
IF "%ACCOUNT_CHOSEN%"=="1" EXIT /B 0
SET PROBE_N=1
:probe_again
CALL :home_probe
IF NOT "%PROBE_RC%"=="1" EXIT /B 0
SET /A PROBE_N=PROBE_N+1
:next_name
IF %PROBE_N% GTR 9 GOTO :names_used_up
SET EXISTS_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts/%BT_DEFAULT_ACCOUNT%_%PROBE_N%" -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT"') DO SET EXISTS_CODE=%%C
IF NOT "%EXISTS_CODE%"=="200" GOTO :name_free
SET /A PROBE_N=PROBE_N+1
GOTO :next_name
:name_free
echo.
echo The home folder of %BT_TEST_ACCOUNT% is left over from an earlier run and belongs to another uid,
echo so the account cannot create folders in it. A new name is used: %BT_DEFAULT_ACCOUNT%_%PROBE_N%.
echo Deleting the account %BT_TEST_ACCOUNT% ^(its home folder stays^)...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts/%BT_TEST_ACCOUNT%" ^
  -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -w "\nHTTP %%{http_code}\n"
SET BT_RUN_ACCOUNT=%BT_DEFAULT_ACCOUNT%_%PROBE_N%
CALL "%~dp0settings.bat"
echo.
echo Account %BT_TEST_ACCOUNT%: scenario 2.1 with %BT_INBOUND_ONLY_COUNT% file^(s^), scenario 2.2 with %BT_IN_AND_OUT_COUNT% file^(s^).
echo.
echo --- again: 01.accounts_POST.bat for %BT_TEST_ACCOUNT% ---
CALL :run_one 01.accounts_POST.bat
IF DEFINED STEP_FAILED EXIT /B 1
REM The count before the run is the new account's own
SET REPORT_LOG=%TEMP%\bt_report_%RANDOM%.log
CALL "%~dp0billable_GET_report.bat" before > "%REPORT_LOG%"
CALL :today_count "%BT_TEST_ACCOUNT%" BEFORE_TEST
IF EXIST "%REPORT_LOG%" DEL "%REPORT_LOG%"
GOTO :probe_again
:names_used_up
echo.
echo The home folder of %BT_TEST_ACCOUNT% is left over from an earlier run, and so is every name up to %BT_DEFAULT_ACCOUNT%_9
echo ^(or the account exists^). Remove the old home folders, or run 00.run_all.bat ANOTHER_NAME.
echo Run 99.cleanup_DELETE.bat %BT_TEST_ACCOUNT% to remove what this created.
SET STEP_FAILED=1
EXIT /B 1

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
