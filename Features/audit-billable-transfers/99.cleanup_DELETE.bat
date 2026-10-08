@echo off
REM ==============================================================================
REM Script Name: 99.cleanup_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Removes everything the other examples created: the composite routes, the
REM simple routes, the template, the subscriptions, the application, the eight
REM sites, the folders in the test account's home, the test account itself, and
REM then this test account's folder in each partner. A partner account is deleted
REM too, once no other test account's site logs in as it any more.
REM
REM Usage:
REM 99.cleanup_DELETE.bat [ACCOUNT]
REM
REM   ACCOUNT  the test account to remove, with everything derived from its name
REM            (default btTestAccount). Use the same name given to 00.run_all.bat.
REM
REM Risk: write
REM
REM Notes:
REM - Deletes the objects named in settings.bat, on the account named there. Check
REM   the names before running it.
REM - Everything is found by name, by listing the collection page by page, so it
REM   works even if the ids saved by the earlier examples are gone. Anything
REM   already gone (HTTP 404) is reported and skipped.
REM - The folders are emptied and removed while their account still exists, so it
REM   needs settings.local.bat with BT_ACCOUNT_PASSWORD. Without it, they are left
REM   in place and only the accounts are deleted.
REM - The partners are shared by every test account. Only this test account's own
REM   folder in them is removed, and a partner stays while another test account's
REM   site still logs in as it.
REM - Confirmed directly (5.5-20260924): GET and DELETE of a folder that does not exist are both a 404
REM   (also directly in a home folder left by an account of another uid), which is why a 404 is "gone"
REM   and a 403 is "refused".
REM - Exits 1 when something could not be deleted (the server refused, a list could not
REM   be read, a folder or account could not be checked), and says what is left. The
REM   saved ids in state.local.bat are then kept, and running it again tries again.
REM   Only when everything is gone is the file removed. A partner is never deleted when
REM   the list of sites that log in as it could not be read.
REM - Uses PowerShell to read the JSON.
REM ==============================================================================

SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
IF NOT "%~1"=="" (
    ECHO %~1| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
        echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~1
        EXIT /B 2
    )
    SET BT_RUN_ACCOUNT=%~1
)
CALL "%~dp0settings.bat"

SET REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET BASE_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0
SET PAGE_SIZE=100

REM What could not be deleted, one line each, for the summary at the end
SET LEFT_FILE=%TEMP%\bt_left_%RANDOM%.txt
TYPE NUL > "%LEFT_FILE%"

REM The composite routes refer to the simple routes, so they go first
SET FIND_FILTER=$_.name -like ($env:BT_COMPOSITE_ROUTE_PREFIX + '*')
SET FIND_OUTPUT=$_.id
CALL :delete_all routes "type=COMPOSITE&"
SET FIND_FILTER=$_.name -like ($env:BT_SIMPLE_ROUTE_PREFIX + '*')
CALL :delete_all routes "type=SIMPLE&"
SET FIND_FILTER=$_.name -eq $env:BT_TEMPLATE_ROUTE
CALL :delete_all routes "type=TEMPLATE&"
SET FIND_FILTER=$_.account -eq $env:BT_TEST_ACCOUNT -and $_.application -eq $env:BT_APPLICATION
CALL :delete_all subscriptions ""
SET FIND_FILTER=$_.name -eq $env:BT_APPLICATION
SET FIND_OUTPUT=$_.name
CALL :delete_all applications ""
SET FIND_FILTER=$_.account -eq $env:BT_TEST_ACCOUNT -and ($_.name -like ($env:BT_PULL_SITE_PREFIX + '*') -or $_.name -eq $env:BT_PUSH_SITE_1 -or $_.name -eq $env:BT_PUSH_SITE_2)
SET FIND_OUTPUT=$_.id
CALL :delete_all sites ""

REM The test account: its folders, then the account
CALL :account_state "%BT_TEST_ACCOUNT%"
IF "%ACCOUNT_STATE%"=="there" (
    CALL :remove_folders "%BT_TEST_ACCOUNT%" "%BT_SUBSCRIPTION_FOLDER%/s1" "%BT_SUBSCRIPTION_FOLDER%/s2" "%BT_SUBSCRIPTION_FOLDER%/s3" "%BT_SUBSCRIPTION_FOLDER%/s4" "%BT_SUBSCRIPTION_FOLDER%/s5" "%BT_SUBSCRIPTION_FOLDER%/s6" "%BT_SUBSCRIPTION_FOLDER%"
    CALL :delete_account "%BT_TEST_ACCOUNT%"
)
IF "%ACCOUNT_STATE%"=="gone" echo The account %BT_TEST_ACCOUNT% does not exist. Nothing to delete.
IF "%ACCOUNT_STATE%"=="unknown" (
    echo Could not tell whether the account %BT_TEST_ACCOUNT% exists ^(HTTP %AR_ADMIN_CODE%^).
    CALL :note_left "the account %BT_TEST_ACCOUNT% and its folders (could not check that it exists, HTTP %AR_ADMIN_CODE%)"
)

REM The partners: this test account's folder in each, then the partner itself,
REM unless another test account's site still logs in as it
CALL :clean_partner "%BT_PULL_PARTNER%" "%BT_DROP_FOLDER%" "%BT_RUN_FOLDER%"
CALL :clean_partner "%BT_PUSH_PARTNER%" "%BT_DELIVERED_1_FOLDER%" "%BT_DELIVERED_2_FOLDER%" "%BT_RUN_FOLDER%"

SET LEFT_SIZE=0
FOR %%F IN ("%LEFT_FILE%") DO SET LEFT_SIZE=%%~zF
IF NOT "%LEFT_SIZE%"=="0" GOTO :not_everything
IF EXIST "%LEFT_FILE%" DEL "%LEFT_FILE%"
IF EXIST "%~dp0state.local.bat" DEL "%~dp0state.local.bat"
EXIT /B 0

:not_everything
echo.
echo Not everything was removed. Left on the server:
TYPE "%LEFT_FILE%"
IF EXIST "%LEFT_FILE%" DEL "%LEFT_FILE%"
echo The saved ids in %~dp0state.local.bat are kept. Fix the cause, then run 99.cleanup_DELETE.bat %BT_TEST_ACCOUNT% again.
EXIT /B 1

REM note_left TEXT: puts one line on the list of what could not be deleted
:note_left
>> "%LEFT_FILE%" echo   %~1
EXIT /B 0

REM delete_all COLLECTION QUERY
REM   Lists COLLECTION page by page, keeps the objects that FIND_FILTER (a
REM   PowerShell condition on $_) matches, and deletes each by FIND_OUTPUT. The
REM   ids are found first, then deleted, so that deleting does not shift pages. A list
REM   the server refuses, and a delete it refuses (other than a 404, which means it is
REM   gone), go on the list of what is left.
:delete_all
SET COLLECTION=%~1
SET QUERY=%~2
SET OFFSET=0
SET PAGE_FILE=%TEMP%\bt_page_%RANDOM%.json
SET PAGE_HEADERS=%TEMP%\bt_page_headers_%RANDOM%.txt
SET IDS_FILE=%TEMP%\bt_ids_%RANDOM%.txt
TYPE NUL > "%IDS_FILE%"

:next_page
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%BASE_URL%/%COLLECTION%?%QUERY%offset=%OFFSET%&limit=%PAGE_SIZE%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -D "%PAGE_HEADERS%" > "%PAGE_FILE%"
SET PAGE_CODE=
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%PAGE_HEADERS%"') DO SET PAGE_CODE=%%C
IF EXIST "%PAGE_HEADERS%" DEL "%PAGE_HEADERS%"
IF NOT DEFINED PAGE_CODE SET PAGE_CODE=000
IF NOT "%PAGE_CODE:~0,1%"=="2" GOTO :list_refused

powershell -NoProfile -Command "try { $f = [scriptblock]::Create($env:FIND_FILTER); $o = [scriptblock]::Create($env:FIND_OUTPUT); (Get-Content -Raw $env:PAGE_FILE | ConvertFrom-Json).result | Where-Object $f | ForEach-Object $o } catch { }" >> "%IDS_FILE%"

SET COUNT=0
FOR /F %%C IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:PAGE_FILE | ConvertFrom-Json).result).Count } catch { 0 }"') DO SET COUNT=%%C
IF %COUNT% GEQ %PAGE_SIZE% (
    SET /A OFFSET=%OFFSET%+%PAGE_SIZE%
    GOTO :next_page
)

SET FOUND=0
FOR /F "usebackq delims=" %%I IN ("%IDS_FILE%") DO CALL :delete_object %COLLECTION% %%I
IF "%FOUND%"=="0" echo No %COLLECTION% to delete.

IF EXIST "%PAGE_FILE%" DEL "%PAGE_FILE%"
IF EXIST "%IDS_FILE%" DEL "%IDS_FILE%"
EXIT /B 0

:list_refused
echo The list of %COLLECTION% could not be read ^(HTTP %PAGE_CODE%^), so none of them was deleted.
CALL :note_left "%COLLECTION%: the list could not be read (HTTP %PAGE_CODE%)"
IF EXIST "%PAGE_FILE%" DEL "%PAGE_FILE%"
IF EXIST "%IDS_FILE%" DEL "%IDS_FILE%"
EXIT /B 0

:delete_object
SET FOUND=1
echo Deleting %1 %2...
CALL "%~dp0..\lib\admin_calls.bat" delete "%1/%2"
IF NOT ERRORLEVEL 1 EXIT /B 0
IF "%AR_ADMIN_CODE%"=="404" EXIT /B 0
CALL :note_left "%1 %2 (HTTP %AR_ADMIN_CODE%)"
EXIT /B 0

REM remove_folders: empties and removes every folder these examples made, with
REM the End User API, logged in as the account. Do it while the account exists.
REM clean_partner PARTNER FOLDER...: removes the folders, then the partner if no
REM site logs in as it any more
:clean_partner
SET CP_PARTNER=%~1
CALL :account_state "%CP_PARTNER%"
IF "%ACCOUNT_STATE%"=="gone" (
    echo The account %CP_PARTNER% does not exist. Nothing to delete.
    EXIT /B 0
)
IF "%ACCOUNT_STATE%"=="unknown" (
    echo Could not tell whether the account %CP_PARTNER% exists ^(HTTP %AR_ADMIN_CODE%^).
    CALL :note_left "this test account's folders in %CP_PARTNER% (could not check that it exists, HTTP %AR_ADMIN_CODE%)"
    EXIT /B 0
)
CALL :remove_folders %*
CALL :sites_logging_in_as "%CP_PARTNER%"
IF DEFINED SITES_UNKNOWN (
    echo The list of sites could not be read, so the account %CP_PARTNER% is kept.
    CALL :note_left "the account %CP_PARTNER%: not deleted, because the list of sites that log in as it could not be read"
    EXIT /B 0
)
IF %IN_USE% GTR 0 (
    echo The account %CP_PARTNER% is kept: %IN_USE% site^(s^) of another test account still log in as it.
) ELSE (
    CALL :delete_account "%CP_PARTNER%"
)
EXIT /B 0

REM account_state ACCOUNT: sets ACCOUNT_STATE to there, gone or unknown (the server
REM did not say, so nothing may be assumed)
:account_state
CALL "%~dp0..\lib\admin_calls.bat" exists "accounts/%~1"
IF ERRORLEVEL 2 (
    SET ACCOUNT_STATE=unknown
    EXIT /B 0
)
IF ERRORLEVEL 1 (
    SET ACCOUNT_STATE=gone
    EXIT /B 0
)
SET ACCOUNT_STATE=there
EXIT /B 0

REM delete_account ACCOUNT: a refused delete, other than a 404, goes on the list
:delete_account
echo Deleting the account %~1...
CALL "%~dp0..\lib\admin_calls.bat" delete "accounts/%~1"
IF ERRORLEVEL 1 IF NOT "%AR_ADMIN_CODE%"=="404" CALL :note_left "the account %~1 (HTTP %AR_ADMIN_CODE%)"
EXIT /B 0

REM sites_logging_in_as ACCOUNT: sets IN_USE to how many sites, of any account, log in as it
:sites_logging_in_as
SET LOGIN_NAME=%~1
SET IN_USE=0
SET SITES_UNKNOWN=
SET SITES_OFFSET=0
SET PAGE_FILE=%TEMP%\bt_page_%RANDOM%.json
SET PAGE_HEADERS=%TEMP%\bt_page_headers_%RANDOM%.txt
:sites_next_page
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%BASE_URL%/sites?offset=%SITES_OFFSET%&limit=%PAGE_SIZE%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -D "%PAGE_HEADERS%" > "%PAGE_FILE%"
SET PAGE_CODE=
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%PAGE_HEADERS%"') DO SET PAGE_CODE=%%C
IF EXIST "%PAGE_HEADERS%" DEL "%PAGE_HEADERS%"
IF NOT DEFINED PAGE_CODE SET PAGE_CODE=000
IF NOT "%PAGE_CODE:~0,1%"=="2" (
    SET SITES_UNKNOWN=1
    IF EXIST "%PAGE_FILE%" DEL "%PAGE_FILE%"
    EXIT /B 0
)
SET PAGE_IN_USE=0
FOR /F %%C IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:PAGE_FILE | ConvertFrom-Json).result | Where-Object { $_.userName -eq $env:LOGIN_NAME }).Count } catch { 0 }"') DO SET PAGE_IN_USE=%%C
SET /A IN_USE=%IN_USE%+%PAGE_IN_USE%
SET COUNT=0
FOR /F %%C IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:PAGE_FILE | ConvertFrom-Json).result).Count } catch { 0 }"') DO SET COUNT=%%C
IF %COUNT% GEQ %PAGE_SIZE% (
    SET /A SITES_OFFSET=%SITES_OFFSET%+%PAGE_SIZE%
    GOTO :sites_next_page
)
IF EXIST "%PAGE_FILE%" DEL "%PAGE_FILE%"
EXIT /B 0

REM remove_folders ACCOUNT FOLDER...: empties and removes each folder, in order,
REM with the End User API, logged in as ACCOUNT. Do it while the account exists.
:remove_folders
SET EU_ACCOUNT=%~1
SHIFT /1
IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set, so the folders of %EU_ACCOUNT% are left in place.
    EXIT /B 0
)
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 (
    echo The folders of %EU_ACCOUNT% are left in place.
    CALL :note_left "the folders of %EU_ACCOUNT% (could not log in)"
    EXIT /B 0
)
:remove_next_folder
IF "%~1"=="" GOTO :remove_folders_done
CALL :remove_one_folder "%~1"
SHIFT /1
GOTO :remove_next_folder
:remove_folders_done
CALL "%~dp0..\lib\enduser.bat" logout
EXIT /B 0

:remove_one_folder
SET CLEAN_FOLDER=%~1
CALL "%~dp0..\lib\enduser.bat" call GET "files%CLEAN_FOLDER%" ""
IF "%EU_CODE%"=="404" (
    echo The folder %CLEAN_FOLDER% of %EU_ACCOUNT% is not there.
    EXIT /B 0
)
SET LIST_FILE=%TEMP%\bt_clean_%RANDOM%.txt
powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile } | ForEach-Object { $_.fileName } } catch { }" > "%LIST_FILE%"
FOR /F "usebackq delims=" %%N IN ("%LIST_FILE%") DO CALL :remove_one_file "%CLEAN_FOLDER%" "%%N"
IF EXIST "%LIST_FILE%" DEL "%LIST_FILE%"
echo Deleting the folder %CLEAN_FOLDER% of %EU_ACCOUNT%...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files%CLEAN_FOLDER%" ""
SET DELETE_RC=%ERRORLEVEL%
echo HTTP %EU_CODE%
IF NOT "%DELETE_RC%"=="0" IF NOT "%EU_CODE%"=="404" CALL :note_left "the folder %CLEAN_FOLDER% of %EU_ACCOUNT% (HTTP %EU_CODE%)"
EXIT /B 0

:remove_one_file
echo Deleting the file %~1/%~2...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files%~1/%~2" ""
SET DELETE_RC=%ERRORLEVEL%
echo HTTP %EU_CODE%
IF NOT "%DELETE_RC%"=="0" IF NOT "%EU_CODE%"=="404" CALL :note_left "the file %~1/%~2 of %EU_ACCOUNT% (HTTP %EU_CODE%)"
EXIT /B 0
