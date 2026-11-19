@echo off
REM ==============================================================================
REM Script Name: run_business_units.bat
REM Author: Plamen Milenkov
REM Created: 2026-11-18
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Runs the transfers of this feature for the users of two business units, so that
REM the two units end with a different number of transfers:
REM
REM   1. Creates the two business units (BT_BU_1 and BT_BU_2), each with its base
REM      folder <BT_HOME_ROOT>/<unit>, using the `/businessUnits` endpoint.
REM   2. Runs the whole feature (00.run_all.bat) once for each user: BT_BU_1_USERS
REM      users in the first unit (3 by default) and BT_BU_2_USERS in the second (1
REM      by default). A user is a test account, created in its unit, with its home
REM      folder inside the unit's base folder. Each user does the same transfers as
REM      one run of 00.run_all.bat, so the first unit does three times the transfers
REM      of the second.
REM   3. Counts, for each unit, the transfers of its users since the run started:
REM      all of them, and the billable ones, next to what the rule predicts.
REM
REM Usage:
REM run_business_units.bat [--cleanup ^| --remove]
REM
REM   (no option)  create, run and report, and leave everything in place
REM   --cleanup    after the report, remove everything again
REM   --remove     only remove what an earlier run left (the users with their objects, then
REM                the two business units), without running anything
REM
REM Risk: write
REM
REM Notes:
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat. The names, the
REM   number of users per unit and the number of files per user are in settings.bat.
REM - The users are named after their unit: btBusinessUnit1User1, btBusinessUnit1User2, and so on.
REM - The two partner accounts are shared by all the users, and stay in the default unit:
REM   the transfers counted for a unit are those of its users' own accounts.
REM - The transfer log has no business unit filter, so a unit's count is the sum of the
REM   counts of its users (the `account` filter of `/logs/transfers`, since the start of
REM   this run). Run it again with the same names the same day and the counts include the
REM   earlier run: --remove first.
REM - Stops at the first user whose run fails, and leaves everything in place to look at.
REM - A unit is deleted only after its users, and the server refuses to delete a unit that
REM   still has accounts: --remove says so and exits 1.
REM ==============================================================================

REM Everything this sets ends with this script
SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0

SET MODE=run
IF NOT "%~2"=="" GOTO :usage
IF "%~1"=="" GOTO :mode_done
IF /I "%~1"=="--cleanup" ( SET MODE=cleanup& GOTO :mode_done )
IF /I "%~1"=="--remove" ( SET MODE=remove& GOTO :mode_done )
:usage
echo Usage: run_business_units.bat [--cleanup ^| --remove]
EXIT /B 2
:mode_done

SET BT_RUN_BUSINESS_UNIT=
CALL "%~dp0settings.bat"

echo %BT_BU_1_USERS%| findstr /R "^[1-9][0-9]*$" >nul
IF ERRORLEVEL 1 (
    echo The number of users per unit must be a whole number, 1 or more: %BT_BU_1_USERS%
    EXIT /B 2
)
echo %BT_BU_2_USERS%| findstr /R "^[1-9][0-9]*$" >nul
IF ERRORLEVEL 1 (
    echo The number of users per unit must be a whole number, 1 or more: %BT_BU_2_USERS%
    EXIT /B 2
)
IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

IF NOT "%MODE%"=="remove" GOTO :not_remove
CALL :remove_all
EXIT /B %ERRORLEVEL%
:not_remove

REM A time-stamp for the counts: only transfers after it are counted
FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "$c=[Globalization.CultureInfo]::InvariantCulture; $n=Get-Date; $n.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $n.ToString('zzz').Replace(':','')"') DO SET RUN_START=%%S

echo === Step 1: the business units ===
FOR %%U IN (%BT_BU_1% %BT_BU_2%) DO (
    CALL :create_unit %%U
    IF ERRORLEVEL 1 EXIT /B 1
)

echo.
echo === Step 2: the transfers of each user ===
FOR /L %%I IN (1,1,%BT_BU_1_USERS%) DO (
    CALL :run_user %BT_BU_1% %%I
    IF ERRORLEVEL 1 EXIT /B 1
)
FOR /L %%I IN (1,1,%BT_BU_2_USERS%) DO (
    CALL :run_user %BT_BU_2% %%I
    IF ERRORLEVEL 1 EXIT /B 1
)

REM What the rule predicts a user adds: FILES is every file it pulls (inbound only, in and out,
REM and 5 more from 2.3 to 2.6), and the account has FILES inbound plus 5 billable pushes
SET /A FILES=%BT_INBOUND_ONLY_COUNT% + %BT_IN_AND_OUT_COUNT% + 5
SET /A PREDICT_BILLABLE=%FILES% + 5

echo.
echo === Step 3: the transfers of each business unit, since this run started ===
echo.
echo   business unit          users  all transfers       billable  the rule predicts (billable)
SET MATCHED=1
CALL :unit_row %BT_BU_1% %BT_BU_1_USERS%
CALL :unit_row %BT_BU_2% %BT_BU_2_USERS%
echo.
echo Each user does the transfers of one 00.run_all.bat run, so a unit's count is its number of users
echo times one run's: the two units differ by their number of users.
IF NOT "%MATCHED%"=="1" (
    echo A unit did not add what the rule predicts, or a count could not be read. A push still under
    echo way when this was counted shows up in a later count: billable_GET_report.bat ^<user^> shows each user.
)

IF "%MODE%"=="cleanup" (
    echo.
    echo === Cleanup ===
    CALL :remove_all
    EXIT /B %ERRORLEVEL%
)
echo.
echo Run run_business_units.bat --remove to remove everything this created.
IF "%MATCHED%"=="1" EXIT /B 0
EXIT /B 1

REM create_unit NAME: creates a business unit, or reuses it when it is there
:create_unit
CALL "%~dp0..\lib\admin_calls.bat" exists "businessUnits/%~1"
IF NOT ERRORLEVEL 1 (
    echo The business unit %~1 is already there. Reused.
    EXIT /B 0
)
echo Creating the business unit %~1, base folder %BT_HOME_ROOT%/%~1...
SET UNIT_NAME=%~1
SET UNIT_BODY=%TEMP%\bt_unit_%RANDOM%.json
powershell -NoProfile -Command "@{ name=$env:UNIT_NAME; baseFolder=($env:BT_HOME_ROOT + '/' + $env:UNIT_NAME) } | ConvertTo-Json -Compress" > "%UNIT_BODY%"
CALL "%~dp0..\lib\post_admin.bat" businessUnits "%UNIT_BODY%"
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%UNIT_BODY%" DEL "%UNIT_BODY%"
IF NOT "%POST_RESULT%"=="0" echo Stopped: the business unit %~1 could not be created.
EXIT /B %POST_RESULT%

REM run_user UNIT NUMBER: the whole feature for one user of a unit; shows only its analysis
:run_user
SET USER_UNIT=%~1
SET USER_NAME=%~1User%~2
echo.
echo --- %USER_NAME%, in %USER_UNIT% ---
SET USER_LOG=%TEMP%\bt_user_%RANDOM%.log
SET BT_RUN_BUSINESS_UNIT=%USER_UNIT%
CALL "%~dp000.run_all.bat" "%USER_NAME%" > "%USER_LOG%" 2>&1
SET USER_RC=%ERRORLEVEL%
SET BT_RUN_BUSINESS_UNIT=
REM Only the analysis of the run, not its whole output
powershell -NoProfile -Command "$l=@(Get-Content $env:USER_LOG); $i=0; for ($k=0; $k -lt $l.Count; $k++) { if ($l[$k] -match '^=== Step 4') { $i=$k; break } }; if ($i -gt 0) { $l[$i..($l.Count-1)] | Where-Object { $_ -notmatch '^Run .*99.cleanup' } }"
IF NOT "%USER_RC%"=="0" (
    echo.
    echo Stopped: the run of %USER_NAME% failed. The last lines of its output:
    powershell -NoProfile -Command "Get-Content $env:USER_LOG -Tail 15"
    IF EXIST "%USER_LOG%" DEL "%USER_LOG%"
    echo Nothing was cleaned up. run_business_units.bat --remove removes it all.
    EXIT /B 1
)
IF EXIST "%USER_LOG%" DEL "%USER_LOG%"
EXIT /B 0

REM transfer_count ACCOUNT BILLABLE: sets TRANSFER_COUNT to the transfers of an account since the
REM start of this run; BILLABLE is 1 for the billable ones only. Empty when it could not be read.
:transfer_count
SET COUNT_ACCOUNT=%~1
SET COUNT_FILE=%TEMP%\bt_count_%RANDOM%.json
SET TRANSFER_COUNT=
SET BILLABLE_FILTER=
IF "%~2"=="1" SET BILLABLE_FILTER=--data-urlencode "isBillable=true"
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
  %BILLABLE_FILTER% --data-urlencode "account=%COUNT_ACCOUNT%" ^
  --data-urlencode "startTimeAfter=%RUN_START%" --data-urlencode "limit=1" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" > "%COUNT_FILE%"
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:COUNT_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET TRANSFER_COUNT=%%N
IF EXIST "%COUNT_FILE%" DEL "%COUNT_FILE%"
EXIT /B 0

REM unit_row UNIT USERS: one line of the table, the sum over the unit's users
:unit_row
SET ROW_UNIT=%~1
SET ROW_USERS=%~2
SET TOTAL_ALL=0
SET TOTAL_BILLABLE=0
SET ROW_READABLE=1
FOR /L %%I IN (1,1,%ROW_USERS%) DO CALL :unit_user %%I
SET /A PREDICTED=%PREDICT_BILLABLE% * %ROW_USERS%
IF "%ROW_READABLE%"=="0" (
    echo   %ROW_UNIT%  %ROW_USERS%  ?  ?  %PREDICTED%
    SET MATCHED=0
    EXIT /B 0
)
SET DIFFERS=
IF NOT "%TOTAL_BILLABLE%"=="%PREDICTED%" ( SET DIFFERS=   differs& SET MATCHED=0 )
echo   %ROW_UNIT%  %ROW_USERS%  %TOTAL_ALL%  %TOTAL_BILLABLE%  %PREDICTED%%DIFFERS%
EXIT /B 0

:unit_user
CALL :transfer_count "%ROW_UNIT%User%~1" 0
SET USER_ALL=%TRANSFER_COUNT%
CALL :transfer_count "%ROW_UNIT%User%~1" 1
IF "%USER_ALL%"=="" ( SET ROW_READABLE=0& EXIT /B 0 )
IF "%TRANSFER_COUNT%"=="" ( SET ROW_READABLE=0& EXIT /B 0 )
SET /A TOTAL_ALL=%TOTAL_ALL% + %USER_ALL%
SET /A TOTAL_BILLABLE=%TOTAL_BILLABLE% + %TRANSFER_COUNT%
EXIT /B 0

REM remove_all: each user with everything it owns, then the two business units
:remove_all
SET REMOVE_FAILED=0
FOR /L %%I IN (1,1,%BT_BU_1_USERS%) DO CALL :remove_user %BT_BU_1% %%I
FOR /L %%I IN (1,1,%BT_BU_2_USERS%) DO CALL :remove_user %BT_BU_2% %%I
FOR %%U IN (%BT_BU_1% %BT_BU_2%) DO CALL :remove_unit %%U
EXIT /B %REMOVE_FAILED%

:remove_user
echo.
echo --- removing %~1User%~2 ---
SET BT_RUN_BUSINESS_UNIT=%~1
CALL "%~dp099.cleanup_DELETE.bat" "%~1User%~2"
IF ERRORLEVEL 1 SET REMOVE_FAILED=1
SET BT_RUN_BUSINESS_UNIT=
EXIT /B 0

:remove_unit
CALL "%~dp0..\lib\admin_calls.bat" exists "businessUnits/%~1"
IF NOT ERRORLEVEL 1 (
    echo.
    echo Deleting the business unit %~1...
    CALL "%~dp0..\lib\admin_calls.bat" delete "businessUnits/%~1"
    IF ERRORLEVEL 1 SET REMOVE_FAILED=1
    EXIT /B 0
)
echo.
echo The business unit %~1 is not there.
EXIT /B 0
