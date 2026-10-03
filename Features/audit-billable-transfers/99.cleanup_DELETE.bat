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
REM sites, the folders in the account's home, then the test account itself.
REM
REM Usage:
REM 99.cleanup_DELETE.bat [ACCOUNT]
REM
REM   ACCOUNT  the test account to remove, with everything derived from its name
REM            (default btTestAccount). Use the same name given to 00.run_all.bat.
REM
REM Notes:
REM - Deletes the objects named in settings.bat, on the account named there. Check
REM   the names before running it.
REM - Everything is found by name, by listing the collection page by page, so it
REM   works even if the ids saved by the earlier examples are gone. Anything
REM   already gone is reported and skipped.
REM - The folders are emptied and removed while the account still exists, so it
REM   needs settings.local.bat with BT_ACCOUNT_PASSWORD. Without it, they are left
REM   in place and only the account is deleted.
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

SET ACCOUNT_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%BASE_URL%/accounts/%BT_TEST_ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET ACCOUNT_CODE=%%C
IF "%ACCOUNT_CODE:~0,1%"=="2" (
    CALL :remove_folders
    echo Deleting the account %BT_TEST_ACCOUNT%...
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%BASE_URL%/accounts/%BT_TEST_ACCOUNT%" ^
      -H "accept: */*" -H "%REFERER_HEADER%" -w "\nHTTP %%{http_code}\n"
) ELSE (
    echo The account %BT_TEST_ACCOUNT% does not exist ^(HTTP %ACCOUNT_CODE%^). Nothing to delete.
)

IF EXIST "%~dp0state.local.bat" DEL "%~dp0state.local.bat"
EXIT /B 0

REM delete_all COLLECTION QUERY
REM   Lists COLLECTION page by page, keeps the objects that FIND_FILTER (a
REM   PowerShell condition on $_) matches, and deletes each by FIND_OUTPUT. The
REM   ids are found first, then deleted, so that deleting does not shift pages.
:delete_all
SET COLLECTION=%~1
SET QUERY=%~2
SET OFFSET=0
SET PAGE_FILE=%TEMP%\bt_page_%RANDOM%.json
SET IDS_FILE=%TEMP%\bt_ids_%RANDOM%.txt
TYPE NUL > "%IDS_FILE%"

:next_page
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%BASE_URL%/%COLLECTION%?%QUERY%offset=%OFFSET%&limit=%PAGE_SIZE%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%PAGE_FILE%"

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

:delete_object
SET FOUND=1
echo Deleting %1 %2...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%BASE_URL%/%1/%2" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -w "\nHTTP %%{http_code}\n"
EXIT /B 0

REM remove_folders: empties and removes every folder these examples made, with
REM the End User API, logged in as the account. Do it while the account exists.
:remove_folders
IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set, so the folders are left in place.
    EXIT /B 0
)
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 (
    echo The folders are left in place.
    EXIT /B 0
)
CALL :remove_one_folder "%BT_DROP_FOLDER%"
CALL :remove_one_folder "%BT_DELIVERED_1_FOLDER%"
CALL :remove_one_folder "%BT_DELIVERED_2_FOLDER%"
FOR %%N IN (1,2,3,4,5,6) DO CALL :remove_one_folder "%BT_SUBSCRIPTION_FOLDER%/s%%N"
CALL :remove_one_folder "%BT_SUBSCRIPTION_FOLDER%"
CALL "%~dp0..\lib\enduser.bat" logout
EXIT /B 0

:remove_one_folder
SET CLEAN_FOLDER=%~1
CALL "%~dp0..\lib\enduser.bat" call GET "files%CLEAN_FOLDER%" ""
SET LIST_FILE=%TEMP%\bt_clean_%RANDOM%.txt
powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile } | ForEach-Object { $_.fileName } } catch { }" > "%LIST_FILE%"
FOR /F "usebackq delims=" %%N IN ("%LIST_FILE%") DO CALL :remove_one_file "%CLEAN_FOLDER%" %%N
IF EXIST "%LIST_FILE%" DEL "%LIST_FILE%"
echo Deleting the folder %CLEAN_FOLDER%...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files%CLEAN_FOLDER%" ""
echo HTTP %EU_CODE%
EXIT /B 0

:remove_one_file
echo Deleting the file %1/%2...
CALL "%~dp0..\lib\enduser.bat" call DELETE "files%1/%2" ""
echo HTTP %EU_CODE%
EXIT /B 0
