@echo off
REM ==============================================================================
REM Script Name: 99.cleanup_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Removes what the other examples created: the three routes, the subscription,
REM the application, the two transfer sites, then the test account.
REM
REM Usage:
REM 99.cleanup_DELETE.bat [ACCOUNT]
REM
REM   ACCOUNT  the test account to remove (default arTestAccount). Use the same name
REM            given to 00.run_all.bat, which prints it when it is not the default.
REM
REM Risk: write
REM
REM Notes:
REM - Deletes the objects named in settings.bat, on the account named there. Check
REM   the names before running it.
REM - Everything is found by name, by listing the collection page by page, so it
REM   works even if the ids saved by the earlier examples are gone. Anything that
REM   is already gone (HTTP 404) is reported and skipped.
REM - The folders in AR_CLEAN_FOLDERS (outbound-drop and delivered, which step 4 made,
REM   and subscription) are emptied and removed first, as the account itself, so the account has
REM   to exist and AR_ACCOUNT_PASSWORD has to be set. Without it they stay.
REM - Deleting an account does NOT delete the files in its home folder. A new
REM   account with the same home folder will find them. Delete them with the End
REM   User API if you want an empty start.
REM - Confirmed directly (5.5-20260924): GET and DELETE of a folder that does not exist are both a 404
REM   (also directly in a home folder left by an account of another uid), which is why a 404 is "gone"
REM   and a 403 is "refused".
REM - Exits 1 when something could not be deleted (the server refused, or a list
REM   could not be read), and says what is left. The saved ids in state.local.bat are
REM   then kept, and running it again tries again. Only when everything is gone is
REM   the file removed.
REM - Uses PowerShell to read the JSON.
REM ==============================================================================

REM Everything this sets, including the account name below, ends with this script
SETLOCAL

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
IF NOT "%~2"=="" (
    echo Usage: 99.cleanup_DELETE.bat [ACCOUNT]
    EXIT /B 2
)
IF NOT "%~1"=="" (
    ECHO %~1| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
        echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~1
        EXIT /B 2
    )
    SET AR_RUN_ACCOUNT=%~1
)
CALL "%~dp0settings.bat"

SET REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET BASE_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0
SET PAGE_SIZE=100

REM What could not be deleted, one line each, for the summary at the end
SET LEFT_FILE=%TEMP%\ar_left_%RANDOM%.txt
TYPE NUL > "%LEFT_FILE%"

REM The composite route refers to the others, so it goes first
SET FIND_FILTER=$_.name -eq $env:AR_COMPOSITE_ROUTE
SET FIND_OUTPUT=$_.id
CALL :delete_all routes "type=COMPOSITE&"
SET FIND_FILTER=$_.name -eq $env:AR_SIMPLE_ROUTE
CALL :delete_all routes "type=SIMPLE&"
SET FIND_FILTER=$_.name -eq $env:AR_TEMPLATE_ROUTE
CALL :delete_all routes "type=TEMPLATE&"
SET FIND_FILTER=$_.account -eq $env:AR_TEST_ACCOUNT -and $_.application -eq $env:AR_APPLICATION
CALL :delete_all subscriptions ""
SET FIND_FILTER=$_.name -eq $env:AR_APPLICATION
SET FIND_OUTPUT=$_.name
CALL :delete_all applications ""
SET FIND_FILTER=$_.account -eq $env:AR_TEST_ACCOUNT -and ($_.name -eq $env:AR_PULL_SITE -or $_.name -eq $env:AR_PUSH_SITE)
SET FIND_OUTPUT=$_.id
CALL :delete_all sites ""

CALL "%~dp0..\lib\admin_calls.bat" exists "accounts/%AR_TEST_ACCOUNT%"
IF ERRORLEVEL 2 GOTO :account_unknown
IF ERRORLEVEL 1 GOTO :account_gone
CALL :remove_folders
echo Deleting the account %AR_TEST_ACCOUNT%...
CALL "%~dp0..\lib\admin_calls.bat" delete "accounts/%AR_TEST_ACCOUNT%"
IF ERRORLEVEL 1 IF NOT "%AR_ADMIN_CODE%"=="404" CALL :note_left "the account %AR_TEST_ACCOUNT% (HTTP %AR_ADMIN_CODE%)"
GOTO :account_done
:account_gone
echo The account %AR_TEST_ACCOUNT% does not exist ^(HTTP %AR_ADMIN_CODE%^). Nothing to delete.
GOTO :account_done
:account_unknown
echo Could not tell whether the account %AR_TEST_ACCOUNT% exists ^(HTTP %AR_ADMIN_CODE%^).
CALL :note_left "the account %AR_TEST_ACCOUNT% and its folders (could not check that it exists, HTTP %AR_ADMIN_CODE%)"
:account_done

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
SET AGAIN_CMD=99.cleanup_DELETE.bat
IF NOT "%AR_TEST_ACCOUNT%"=="%AR_DEFAULT_ACCOUNT%" SET AGAIN_CMD=99.cleanup_DELETE.bat %AR_TEST_ACCOUNT%
echo The saved ids in %~dp0state.local.bat are kept. Fix the cause, then run %AGAIN_CMD% again.
EXIT /B 1

REM note_left TEXT: puts one line on the list of what could not be deleted
:note_left
>> "%LEFT_FILE%" echo   %~1
EXIT /B 0

REM delete_all COLLECTION QUERY
REM   Lists COLLECTION page by page, keeps the objects that FIND_FILTER (a PowerShell
REM   condition on $_) matches, and deletes each by FIND_OUTPUT. The ids are found
REM   first, then deleted, so that deleting does not shift the pages. A list the
REM   server refuses, and a delete it refuses (other than a 404, which means it is
REM   gone), go on the list of what is left.
:delete_all
SET COLLECTION=%~1
SET QUERY=%~2
SET OFFSET=0
SET PAGE_FILE=%TEMP%\ar_page_%RANDOM%.json
SET PAGE_HEADERS=%TEMP%\ar_page_headers_%RANDOM%.txt
SET IDS_FILE=%TEMP%\ar_ids_%RANDOM%.txt
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

REM remove_folders
REM   Empties and removes the folders in AR_CLEAN_FOLDERS from the account's home, with
REM   the End User API, logged in as the account. Do it while the account still exists.
:remove_folders
IF "%AR_ACCOUNT_PASSWORD%"=="" (
    echo AR_ACCOUNT_PASSWORD is not set, so the folders are left in place.
    EXIT /B 0
)
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 (
    echo The folders are left in place.
    CALL :note_left "the folders %AR_CLEAN_FOLDERS% in the home of %AR_TEST_ACCOUNT% (could not log in)"
    EXIT /B 0
)
FOR %%F IN (%AR_CLEAN_FOLDERS%) DO CALL :remove_folder %%F
CALL "%~dp0..\lib\enduser.bat" logout
EXIT /B 0

:remove_folder
SET CLEAN_FOLDER=%1
CALL "%~dp0..\lib\enduser.bat" call GET "files/%CLEAN_FOLDER%" ""
IF "%EU_CODE%"=="404" (
    echo The folder %CLEAN_FOLDER% is not there.
    EXIT /B 0
)
SET LIST_FILE=%TEMP%\ar_clean_%RANDOM%.txt
powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile } | ForEach-Object { $_.fileName } } catch { }" > "%LIST_FILE%"
FOR /F "usebackq delims=" %%N IN ("%LIST_FILE%") DO CALL :remove_file "%CLEAN_FOLDER%" "%%N"
IF EXIST "%LIST_FILE%" DEL "%LIST_FILE%"
echo Deleting the folder %CLEAN_FOLDER%...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files/%CLEAN_FOLDER%" ""
SET DELETE_RC=%ERRORLEVEL%
echo HTTP %EU_CODE%
IF NOT "%DELETE_RC%"=="0" IF NOT "%EU_CODE%"=="404" CALL :note_left "the folder %CLEAN_FOLDER% (HTTP %EU_CODE%)"
EXIT /B 0

:remove_file
echo Deleting the file %~1/%~2...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files/%~1/%~2" ""
SET DELETE_RC=%ERRORLEVEL%
echo HTTP %EU_CODE%
IF NOT "%DELETE_RC%"=="0" IF NOT "%EU_CODE%"=="404" CALL :note_left "the file %~1/%~2 (HTTP %EU_CODE%)"
EXIT /B 0
