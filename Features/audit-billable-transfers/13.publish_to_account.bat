@echo off
REM ==============================================================================
REM Script Name: 13.publish_to_account.bat
REM Author: Plamen Milenkov
REM Created: 2026-11-11
REM Location: Sofia
REM ==============================================================================
REM Description:
REM One more scenario, 2.7, with a single Publish to Account step: a file that
REM the test account receives is published by the server, with no partner and no
REM network, to a folder of another account on the same server,
REM partner_to_push_to. It creates what the scenario needs (the folder, the
REM subscription, a route with the one step, a composite route that links them)
REM and sets that account's home folder access level to PUBLIC while it runs,
REM uploads one file to the test account's folder, waits for it to arrive in the
REM other account, and prints the billable count of both accounts before and
REM after, with the transfers behind it.
REM
REM Usage:
REM 13.publish_to_account.bat [ACCOUNT]
REM
REM   ACCOUNT   the test account (default: the one of settings.bat). Run
REM             00.run_all.bat first: this needs its account, application and
REM             route template.
REM
REM Risk: write
REM
REM Notes:
REM - Needs the objects of 00.run_all.bat, and BT_ACCOUNT_PASSWORD (see settings.bat).
REM - The step is the API's `Publish` step (the product's "Publish to Account"):
REM   targetAccountExpression is the other account, targetFolderExpression a
REM   folder in it that the step makes when it is not there.
REM - The target account must accept files from another account: with its home
REM   folder access level PRIVATE the step fails ("Not allowed to publish files to
REM   home folder of target account"). It is set to PUBLIC for the run, and put back.
REM - The route and the subscription are named after the test account like the
REM   others (<account>SimpleRoute7, <account>CompositeRoute7), so
REM   99.cleanup_DELETE.bat removes them, and the folders, with the rest.
REM - The upload goes to a subscription folder of the test account: that is what
REM   starts the route. No pull site is needed.
REM - Uses PowerShell to build the JSON bodies and to read the responses.
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

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)
IF NOT DEFINED BT_ID_TEMPLATE (
    echo BT_ID_TEMPLATE is not saved. Run 00.run_all.bat first.
    EXIT /B 1
)

SET ADMIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0
SET WORK=%TEMP%\bt_publish_%RANDOM%
MKDIR "%WORK%"
SET RESTORE_LEVEL=

REM The folder, in the test account, that starts the route
echo Creating the folder %BT_PUBLISH_SOURCE_FOLDER% in %BT_TEST_ACCOUNT%...
SET EU_ACCOUNT=%BT_TEST_ACCOUNT%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 GOTO :fail
SET BODY_FILE=%WORK%\folder.json
powershell -NoProfile -Command "@{ isDirectory=$true; isRegularFile=$false; isSymbolicLink=$false; isOther=$false; isShared=$false } | ConvertTo-Json -Compress" > "%BODY_FILE%"
SET FOLDER_PATH=%BT_PUBLISH_SOURCE_FOLDER:~1%
CALL "%~dp0..\lib\enduser.bat" call POST "files/%FOLDER_PATH%" "application/json" "%BODY_FILE%"
echo HTTP %EU_CODE%
IF "%EU_CODE%"=="409" echo The folder is there already: going on.
IF NOT "%EU_CODE%"=="409" IF NOT "%EU_CODE:~0,1%"=="2" (
    TYPE "%EU_BODY_FILE%"
    echo.
    CALL "%~dp0..\lib\enduser.bat" logout
    GOTO :fail
)
CALL "%~dp0..\lib\enduser.bat" logout

REM The other account must accept files from another account. A Private home
REM folder (the default) refuses the step: "It can only receive files from itself"
REM (log AR0057), and the step fails with "Not allowed to publish files to home
REM folder of target account". So it is set to PUBLIC for this scenario, and put
REM back afterwards. The folder in it is made by the step.
SET OLD_LEVEL=
FOR /F "delims=" %%L IN ('curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" "%ADMIN_URL%/accounts/%BT_PUSH_PARTNER%" ^| powershell -NoProfile -Command "try { ($input | ConvertFrom-Json).homeFolderAccessLevel } catch { }"') DO SET OLD_LEVEL=%%L
IF NOT "%OLD_LEVEL%"=="PUBLIC" (
    echo Setting the home folder access level of %BT_PUSH_PARTNER% to PUBLIC ^(it was %OLD_LEVEL%^)...
    CALL :set_level PUBLIC
    echo HTTP %LEVEL_CODE%
    IF NOT "%LEVEL_CODE:~0,1%"=="2" GOTO :fail
    SET RESTORE_LEVEL=%OLD_LEVEL%
)

REM The subscription on that folder, the route with the one step, and the composite
REM route that links the two (the same three objects as the other scenarios)
SET BODY_FILE=%WORK%\subscription.json
powershell -NoProfile -Command "@{ type='AdvancedRouting'; application=$env:BT_APPLICATION; account=$env:BT_TEST_ACCOUNT; folder=$env:BT_PUBLISH_SOURCE_FOLDER } | ConvertTo-Json -Compress" > "%BODY_FILE%"
echo Creating the subscription on %BT_PUBLISH_SOURCE_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" subscriptions "%BODY_FILE%" BT_ID_SUBSCRIPTION_7
IF ERRORLEVEL 1 GOTO :fail

SET PUBLISHED_NAME=%BT_PUBLISHED_FOLDER:~1%
SET BODY_FILE=%WORK%\simple.json
SET SIMPLE_NAME=%BT_SIMPLE_ROUTE_PREFIX%7
powershell -NoProfile -Command "$step = @{ type='Publish'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; filenameCollisionResolutionType='OVERWRITE'; targetAccountExpressionType='NAME'; targetAccountExpression=$env:BT_PUSH_PARTNER; targetFolderExpressionType='SIMPLE'; targetFolderExpression=$env:PUBLISHED_NAME; triggerSubscription=$false; actionOnStepFailure='FAIL' }; @{ type='SIMPLE'; name=$env:SIMPLE_NAME; conditionType='ALWAYS'; condition=$true; steps=@($step) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
echo Creating the simple route %SIMPLE_NAME%, with one Publish step to %BT_PUSH_PARTNER%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" BT_ID_SIMPLE_7
IF ERRORLEVEL 1 GOTO :fail

REM post_admin.bat keeps the ids in state.local.bat: read them back
CALL "%~dp0state.local.bat"
SET BODY_FILE=%WORK%\composite.json
SET COMPOSITE_NAME=%BT_COMPOSITE_ROUTE_PREFIX%7
powershell -NoProfile -Command "@{ type='COMPOSITE'; account=$env:BT_TEST_ACCOUNT; name=$env:COMPOSITE_NAME; conditionType='MATCH_ALL'; routeTemplate=$env:BT_ID_TEMPLATE; subscriptions=@($env:BT_ID_SUBSCRIPTION_7); steps=@(@{ type='ExecuteRoute'; status='ENABLED'; autostart=$false; executeRoute=$env:BT_ID_SIMPLE_7 }) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
echo Creating the composite route %COMPOSITE_NAME%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" BT_ID_COMPOSITE_7
IF ERRORLEVEL 1 GOTO :fail

REM The billable count of today, before
FOR /F "delims=" %%S IN ('powershell -NoProfile -Command "$c=[Globalization.CultureInfo]::InvariantCulture; $n=Get-Date; $n.ToString('ddd, dd MMM yyyy HH:mm:ss ', $c) + $n.ToString('zzz').Replace(':','')"') DO SET RUN_START_RAW=%%S
CALL :report before
echo.
echo Billable transfers of today, before:
echo   %BT_TEST_ACCOUNT%   %COUNT_TEST%
echo   %BT_PUSH_PARTNER%   %COUNT_PUSH%
SET BEFORE_TEST=%COUNT_TEST%
SET BEFORE_PUSH=%COUNT_PUSH%

REM One file into the folder: the subscription starts the route, the route publishes
echo.
echo Uploading %BT_FILE_PUBLISH% to %BT_PUBLISH_SOURCE_FOLDER% of %BT_TEST_ACCOUNT%...
echo Scenario 2.7: published to another account.> "%WORK%\%BT_FILE_PUBLISH%"
SET EU_ACCOUNT=%BT_TEST_ACCOUNT%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 GOTO :fail
SET UP_PATH=%BT_PUBLISH_SOURCE_FOLDER%/%BT_FILE_PUBLISH%
SET BODY_FILE=%WORK%\upload.json
powershell -NoProfile -Command "@{ operation='Upload'; filePath=$env:UP_PATH; customAttributes=@{ transferMode='BINARY' } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"
CALL "%~dp0..\lib\enduser.bat" call POST fileOperations "application/json" "%BODY_FILE%"
SET OPERATION_ID=
FOR /F "delims=" %%O IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).id } catch { }"') DO SET OPERATION_ID=%%O
IF NOT DEFINED OPERATION_ID (
    echo No operation id came back ^(HTTP %EU_CODE%^):
    TYPE "%EU_BODY_FILE%"
    echo.
    CALL "%~dp0..\lib\enduser.bat" logout
    GOTO :fail
)
CALL "%~dp0..\lib\enduser.bat" call PUT "fileOperations/%OPERATION_ID%" "application/octet-stream" "%WORK%\%BT_FILE_PUBLISH%"
echo HTTP %EU_CODE%
CALL "%~dp0..\lib\enduser.bat" logout

REM Wait for the file in the other account
echo.
echo Waiting for %BT_FILE_PUBLISH% in %BT_PUBLISHED_FOLDER% of %BT_PUSH_PARTNER%...
SET EU_ACCOUNT=%BT_PUSH_PARTNER%
CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 GOTO :fail
SET WAITED=0
:wait_loop
CALL "%~dp0..\lib\enduser.bat" call GET "files%BT_PUBLISHED_FOLDER%" ""
SET FOUND=0
FOR /F %%C IN ('powershell -NoProfile -Command "try { @((Get-Content -Raw $env:EU_BODY_FILE | ConvertFrom-Json).files | Where-Object { $_.isRegularFile -and $_.fileName -eq $env:BT_FILE_PUBLISH }).Count } catch { 0 }"') DO SET FOUND=%%C
IF %FOUND% GEQ 1 GOTO :arrived
IF %WAITED% GEQ %BT_WAIT_SECONDS% GOTO :arrived
ping -n 4 127.0.0.1 >NUL
SET /A WAITED=%WAITED%+3
GOTO :wait_loop

:arrived
CALL "%~dp0..\lib\enduser.bat" logout
IF %FOUND% LSS 1 (
    echo The file did not arrive within %BT_WAIT_SECONDS% seconds.
    GOTO :fail
)
echo %BT_FILE_PUBLISH% is in %BT_PUBLISHED_FOLDER% of %BT_PUSH_PARTNER%.

ping -n %BT_STEP_PAUSE_SECONDS% 127.0.0.1 >NUL
CALL :report after
echo.
echo Billable transfers of today, after:
SET /A ADDED_TEST=%COUNT_TEST%-%BEFORE_TEST%
SET /A ADDED_PUSH=%COUNT_PUSH%-%BEFORE_PUSH%
echo   %BT_TEST_ACCOUNT%   %COUNT_TEST% ^(added %ADDED_TEST%^)
echo   %BT_PUSH_PARTNER%   %COUNT_PUSH% ^(added %ADDED_PUSH%^)

REM The transfers behind the numbers, by file name
echo.
echo The transfers of %BT_FILE_PUBLISH%:
FOR %%A IN ("%BT_TEST_ACCOUNT%" "%BT_PUSH_PARTNER%") DO CALL :show_transfers %%~A
CALL :restore
RMDIR /S /Q "%WORK%" 2>NUL
EXIT /B 0

:fail
CALL :restore
RMDIR /S /Q "%WORK%" 2>NUL
EXIT /B 1

REM Puts the home folder access level back, when this script changed it
:restore
IF DEFINED RESTORE_LEVEL (
    CALL :set_level %RESTORE_LEVEL%
    echo Putting the home folder access level of %BT_PUSH_PARTNER% back to %RESTORE_LEVEL%: HTTP %LEVEL_CODE%
    SET RESTORE_LEVEL=
)
EXIT /B 0

REM set_level LEVEL: PATCH the home folder access level of the other account
:set_level
SET LEVEL_VALUE=%1
powershell -NoProfile -Command "ConvertTo-Json -Compress @(@{ op='replace'; path='/homeFolderAccessLevel'; value=$env:LEVEL_VALUE })" > "%WORK%\level.json"
SET LEVEL_CODE=
FOR /F %%H IN ('curl -s -k -o NUL -w "%%{http_code}" -X PATCH -u "%ST_USER%:%ST_PASSWORD%" -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "Content-Type: application/json" -d "@%WORK%\level.json" "%ADMIN_URL%/accounts/%BT_PUSH_PARTNER%"') DO SET LEVEL_CODE=%%H
EXIT /B 0

REM report LABEL: the billable count of today of both accounts, from the report script
:report
SET COUNT_TEST=
SET COUNT_PUSH=
CALL "%~dp0billable_GET_report.bat" %1 "%BT_TEST_ACCOUNT%" > "%WORK%\report.txt"
FOR /F "tokens=3 delims=: " %%T IN ('FINDSTR /B /C:"TODAY_COUNT %BT_TEST_ACCOUNT%:" "%WORK%\report.txt"') DO SET COUNT_TEST=%%T
FOR /F "tokens=3 delims=: " %%T IN ('FINDSTR /B /C:"TODAY_COUNT %BT_PUSH_PARTNER%:" "%WORK%\report.txt"') DO SET COUNT_PUSH=%%T
EXIT /B 0

REM show_transfers ACCOUNT: the transfers of the file since this run began
:show_transfers
SET SHOW_ACCOUNT=%1
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "%ADMIN_URL%/logs/transfers" --data-urlencode "account=%SHOW_ACCOUNT%" --data-urlencode "startTimeAfter=%RUN_START_RAW%" --data-urlencode "limit=200" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT" > "%WORK%\transfers.json"
powershell -NoProfile -Command "try { (Get-Content -Raw $env:WORK\transfers.json | ConvertFrom-Json).result | Where-Object { $_.filename -eq $env:BT_FILE_PUBLISH } | ForEach-Object { '  ' + $_.account + '  coreId ' + $_.coreId.Substring(0,8) + '  billable ' + $_.isBillable + '  ' + $_.protocol + '  ' + $_.status } } catch { }"
EXIT /B 0
