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
REM 00.run_all.bat              run steps 01 to 13 and leave everything in place
REM 00.run_all.bat --cleanup    the same, then run 99.cleanup_DELETE.bat at the end
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
REM - To run one step on its own, run its script directly.
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

IF "%CLEANUP%"=="1" (
    echo.
    echo === Cleanup: 99.cleanup_DELETE.bat ===
    CALL "%~dp099.cleanup_DELETE.bat"
) ELSE (
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
echo === Step %N% of %TOTAL%: %NAME% ===
SET LOG=%TEMP%\ar_run_%RANDOM%.log
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

REM The pull and the route run asynchronously: after the pull (11) and after the
REM trigger file fix (12), give them a moment before the next step looks
IF "%NAME:~0,2%"=="11" CALL :pause
IF "%NAME:~0,2%"=="12" CALL :pause
EXIT /B 0

:pause
SET /A PING_COUNT=%AR_STEP_PAUSE_SECONDS%+1
echo.
echo Pausing %AR_STEP_PAUSE_SECONDS% seconds...
ping -n %PING_COUNT% 127.0.0.1 >NUL
EXIT /B 0
