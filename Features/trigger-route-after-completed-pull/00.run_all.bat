@echo off
REM ==============================================================================
REM Script Name: 00.run_all.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Runs the whole feature, start to finish: every numbered example in this folder,
REM in order, 01 to 13. It builds the test account, the sites, the routes and the
REM subscription, puts sample files in place, runs the pull, fixes the trigger file,
REM and shows what arrived in the delivered folder.
REM
REM Usage:
REM 00.run_all.bat [ACCOUNT] [--cleanup]
REM
REM   ACCOUNT      the test account to create and use (default arTestAccount)
REM   --cleanup    the same, then run 99.cleanup_DELETE.bat at the end
REM
REM For example:
REM 00.run_all.bat                       run steps 01 to 13 and leave everything in place
REM 00.run_all.bat test_account          the same, with an account named test_account
REM 00.run_all.bat --cleanup             run steps 01 to 13, then remove everything again
REM 00.run_all.bat test_account --cleanup
REM
REM Risk: write
REM
REM Notes:
REM - It stops at the first step that fails: a non-zero exit, or a line starting
REM   HTTP 4xx or 5xx in its output. Nothing after it runs, and nothing is cleaned up,
REM   so you can look. Fix the problem, then run 99.cleanup_DELETE.bat and start again.
REM - Needs settings.local.bat with AR_ACCOUNT_PASSWORD. See settings.bat.
REM - After step 11 (the pull) and step 12 (the trigger file fix) it pauses
REM   AR_STEP_PAUSE_SECONDS, 5 by default, so the pull and the route can run.
REM - A stale home folder: an account's home folder stays on disk, with its owner,
REM   when the account is deleted, and a new account with another uid cannot
REM   create a folder directly in it (a 403 in step 04). So, only when no account
REM   name was chosen (no ACCOUNT, no AR_TEST_ACCOUNT in settings.local.bat), the
REM   run checks right after step 01 that the test account can create a folder
REM   directly in its home (ar_home_probe, made and removed again). If not, it says
REM   so, deletes that test account only, and moves to the next free name:
REM   <default>_2, _3, up to _9. It stops after _9, and also when the account cannot
REM   be deleted. The cleanup hint and --cleanup use the name it ended on. A name you
REM   chose is never changed: step 04 then fails, with a hint. The probe is
REM   Features\lib\home_folder.bat, shared with the other feature.
REM - The other objects (the sites, routes, application, subscription) keep their
REM   names from settings.bat whatever the account is called, so run one account at a
REM   time: a second run would meet the first one's names.
REM - With --cleanup, the exit code of the run is the cleanup's: 1 when it could not remove
REM   everything (it says what is left).
REM - To run one step on its own, run its script directly.
REM ==============================================================================

REM Everything this sets, including the arguments below, ends with this script,
REM so a later run in the same console starts from the defaults again
SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0

SET CLEANUP=0
SET AR_RUN_ACCOUNT=
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
    echo Usage: 00.run_all.bat [ACCOUNT] [--cleanup]
    EXIT /B 2
)

REM Was an account name given on the command line?
SET ACCOUNT_CHOSEN=0
IF DEFINED AR_RUN_ACCOUNT SET ACCOUNT_CHOSEN=1

REM Loaded after the arguments, so settings.bat applies them, and every step this
REM runs inherits them
CALL "%~dp0settings.bat"

REM Or in settings.local.bat? Then it is never changed.
IF NOT "%AR_TEST_ACCOUNT%"=="%AR_DEFAULT_ACCOUNT%" SET ACCOUNT_CHOSEN=1

IF "%AR_ACCOUNT_PASSWORD%"=="" (
    echo AR_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

REM Every numbered example except this script and the cleanup
SET TOTAL=0
FOR %%S IN ("%~dp0??.*.bat") DO CALL :count %%~nxS
SET N=0
FOR %%S IN ("%~dp0??.*.bat") DO CALL :run_step %%~nxS
IF DEFINED STEP_FAILED EXIT /B 1

echo.
echo All %TOTAL% steps finished.

IF "%CLEANUP%"=="1" GOTO :run_cleanup
CALL :set_cleanup_cmd
echo Run %CLEANUP_CMD% to remove everything this created.
EXIT /B 0

:run_cleanup
echo.
echo === Cleanup: 99.cleanup_DELETE.bat ===
CALL "%~dp099.cleanup_DELETE.bat"
EXIT /B %ERRORLEVEL%

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
echo === Step %N% of %TOTAL%: %NAME% ===
CALL :run_one "%NAME%"
IF DEFINED STEP_FAILED EXIT /B 1

REM The account exists now: can it create a folder in its home?
IF "%NAME:~0,2%"=="01" CALL :ensure_usable_home
IF DEFINED STEP_FAILED EXIT /B 1

REM The pull and the route run asynchronously: after the pull (11) and after the
REM trigger file fix (12), give them a moment before the next step looks
IF "%NAME:~0,2%"=="11" CALL :pause
IF "%NAME:~0,2%"=="12" CALL :pause
EXIT /B 0

REM run_one FILE: runs one example, and sets STEP_FAILED when it fails
:run_one
SET LOG=%TEMP%\ar_run_%RANDOM%.log
CALL "%~dp0%~1" > "%LOG%" 2>&1
SET STEP_RC=%ERRORLEVEL%
TYPE "%LOG%"
SET LOG_HAS_ERROR=
FINDSTR /R /C:"^HTTP [45][0-9][0-9]" "%LOG%" >NUL && SET LOG_HAS_ERROR=1
IF EXIST "%LOG%" DEL "%LOG%"
IF NOT "%STEP_RC%"=="0" SET LOG_HAS_ERROR=1
REM Before the block: %CLEANUP_CMD% in it is read when the whole block is
CALL :set_cleanup_cmd
IF DEFINED LOG_HAS_ERROR (
    echo.
    echo Stopped at step %N% of %TOTAL%: %~1 failed.
    echo Nothing after it was run, and nothing was cleaned up.
    echo Fix it, run %CLEANUP_CMD%, and start again.
    SET STEP_FAILED=1
    EXIT /B 1
)
EXIT /B 0

REM set_cleanup_cmd: sets CLEANUP_CMD to the command that removes what this run made.
REM It names the account when that is not the default one.
:set_cleanup_cmd
SET CLEANUP_CMD=99.cleanup_DELETE.bat
IF NOT "%AR_TEST_ACCOUNT%"=="%AR_DEFAULT_ACCOUNT%" SET CLEANUP_CMD=99.cleanup_DELETE.bat %AR_TEST_ACCOUNT%
EXIT /B 0

REM ensure_usable_home: after step 01. Only when no account name was chosen. The
REM probe and the next free name are in Features\lib\home_folder.bat.
:ensure_usable_home
IF "%ACCOUNT_CHOSEN%"=="1" EXIT /B 0
SET PROBE_N=1
:probe_again
CALL "%~dp0..\lib\home_folder.bat" probe "%AR_TEST_ACCOUNT%" ar_home_probe
IF ERRORLEVEL 2 EXIT /B 0
IF NOT ERRORLEVEL 1 EXIT /B 0
SET /A PROBE_N=%PROBE_N%+1
CALL "%~dp0..\lib\home_folder.bat" next_free "%AR_DEFAULT_ACCOUNT%" %PROBE_N%
SET PROBE_N=%HF_NEXT_N%
IF "%PROBE_N%"=="0" GOTO :names_used_up
CALL "%~dp0..\lib\home_folder.bat" say_stale "%AR_TEST_ACCOUNT%" "%AR_DEFAULT_ACCOUNT%_%PROBE_N%"
CALL "%~dp0..\lib\admin_calls.bat" delete "accounts/%AR_TEST_ACCOUNT%"
IF ERRORLEVEL 1 GOTO :delete_refused
SET AR_RUN_ACCOUNT=%AR_DEFAULT_ACCOUNT%_%PROBE_N%
CALL "%~dp0settings.bat"
echo.
echo --- again: 01.accounts_POST.bat for %AR_TEST_ACCOUNT% ---
CALL :run_one 01.accounts_POST.bat
IF DEFINED STEP_FAILED EXIT /B 1
GOTO :probe_again
:delete_refused
echo The account %AR_TEST_ACCOUNT% could not be deleted, so the run stops here.
SET STEP_FAILED=1
EXIT /B 1
:names_used_up
CALL "%~dp0..\lib\home_folder.bat" say_used_up "%AR_DEFAULT_ACCOUNT%" "%AR_TEST_ACCOUNT%"
SET STEP_FAILED=1
EXIT /B 1

:pause
SET /A PING_COUNT=%AR_STEP_PAUSE_SECONDS%+1
echo.
echo Pausing %AR_STEP_PAUSE_SECONDS% seconds...
ping -n %PING_COUNT% 127.0.0.1 >NUL
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
IF %ARG_N% GTR 1 SET ARG_ERROR=1
EXIT /B 0

:check_account
ECHO %~1| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
    echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~1
    SET ARG_ERROR=1
    EXIT /B 0
)
SET AR_RUN_ACCOUNT=%~1
EXIT /B 0
