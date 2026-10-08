@echo off
REM ==============================================================================
REM Script Name: home_folder.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Shared across Features/. Finds out whether a new test account can use its home
REM folder, and helps a run to move to the next free account name when it cannot.
REM
REM Why: an account's home folder stays on disk, with its owner, when the account is
REM deleted. A new account of that name with ANOTHER uid cannot create a folder
REM directly in it: every such POST (and DELETE) is a 403 "Error occurred while
REM creating file: null", while a folder below an existing one still works, which
REM hides it. Confirmed on 5.5-20260924. Only a new account name gets a new home
REM folder.
REM
REM Usage:
REM CALL home_folder.bat probe ACCOUNT FOLDER
REM CALL home_folder.bat next_free DEFAULT_NAME N
REM CALL home_folder.bat say_stale OLD_NAME NEW_NAME
REM CALL home_folder.bat say_used_up DEFAULT_NAME CURRENT_NAME
REM
REM   probe      logs in as ACCOUNT, makes the top-level folder FOLDER and removes it
REM              again. ERRORLEVEL is 0 when that works, 1 when the home is stale (a
REM              403 "Error occurred while creating file"), 2 when it could not tell
REM              (the login failed, or another error: the example that makes the
REM              folders then reports it). A nested folder would succeed and hide
REM              the problem: it is always top level.
REM   next_free  starting at N, finds the first DEFAULT_NAME_<n>, up to 9, that is not
REM              an account yet. Sets HF_NEXT_N to it, or to 0 when none is free.
REM   say_stale  prints why the run moves from OLD_NAME to NEW_NAME.
REM   say_used_up  prints why the run stops: every name up to DEFAULT_NAME_9 is stale
REM              or taken.
REM
REM The loop itself (probe, next_free, delete the old account with admin_calls.bat,
REM make NEW_NAME the account of the run, create it again) is in each feature's
REM 00.run_all.bat, because a batch file cannot call back into the one that called
REM it. bash has the whole loop in Features/lib/home_folder.sh.
REM
REM Notes:
REM - Confirmed directly (5.5-20260924), on both features: a home folder left by an account of uid
REM   1001 makes the probe of a new account of uid 41733 a 403 "Error occurred while creating file"
REM   (the run moved to <name>_2 or _3 and went on to the end), and the probe of
REM   a usable home succeeds. On a stale home, a GET or DELETE of a top-level folder that does not exist
REM   is a 404, not a 403, so a cleanup can tell "not there" from "refused".
REM - Needs enduser.bat and admin_calls.bat, next to this file.
REM - Sets EU_ACCOUNT, as every login as another account does: the settings.bat of
REM   the feature sets it again when it is called for the new name.
REM ==============================================================================

GOTO :%~1

:probe
SET HF_PROBE_RC=2
SET EU_ACCOUNT=%~2
CALL "%~dp0enduser.bat" login >NUL
IF ERRORLEVEL 1 EXIT /B 2
SET HF_BODY=%TEMP%\ar_probe_%RANDOM%.json
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%HF_BODY%"
CALL "%~dp0enduser.bat" call POST "files/%~3" "application/json" "%HF_BODY%"
IF EXIST "%HF_BODY%" DEL "%HF_BODY%"
SET HF_CODE=%EU_CODE%
IF "%HF_CODE:~0,1%"=="2" SET HF_PROBE_RC=0
IF "%HF_CODE:~0,1%"=="2" CALL "%~dp0enduser.bat" call DELETE "files/%~3" ""
IF "%HF_CODE:~0,1%"=="2" IF ERRORLEVEL 1 echo The probe folder %~3 could not be removed from the home of %~2 ^(HTTP %EU_CODE%^).
IF "%HF_CODE%"=="403" FINDSTR /C:"Error occurred while creating file" "%EU_BODY_FILE%" >NUL && SET HF_PROBE_RC=1
CALL "%~dp0enduser.bat" logout >NUL
EXIT /B %HF_PROBE_RC%

:next_free
SET HF_NEXT_N=%~3
:next_free_loop
IF %HF_NEXT_N% GTR 9 (
    SET HF_NEXT_N=0
    EXIT /B 0
)
CALL "%~dp0admin_calls.bat" exists "accounts/%~2_%HF_NEXT_N%"
IF NOT ERRORLEVEL 1 (
    SET /A HF_NEXT_N=%HF_NEXT_N%+1
    GOTO :next_free_loop
)
EXIT /B 0

:say_stale
echo.
echo The home folder of %~1 is left over from an earlier run and belongs to another uid,
echo so the account cannot create folders in it. A new name is used: %~2.
echo Deleting the account %~1 ^(its home folder stays^)...
EXIT /B 0

:say_used_up
echo.
echo The home folder of %~2 is left over from an earlier run, and so is every name up to %~1_9
echo ^(or the account exists^). Remove the old home folders, or run 00.run_all.bat ANOTHER_NAME.
echo Run 99.cleanup_DELETE.bat %~2 to remove what this created.
EXIT /B 0
