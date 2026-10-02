@echo off
REM ==============================================================================
REM Script Name: 09.subscriptions_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the Advanced Routing subscription that is the point of this feature,
REM using the `/subscriptions` endpoint. It pulls from the pull site, writes a
REM trigger file that lists every pulled file, and runs the route once, after the
REM whole pull, on the files named in that trigger file.
REM
REM Usage:
REM 09.subscriptions_POST.bat
REM
REM Notes:
REM - Uses PowerShell to build the JSON body.
REM - Run 02.sites_POST_pull.bat and 08.applications_POST.bat first: the subscription
REM   names the pull site and the application.
REM - The trigger file name and the trigger condition come from settings.bat, so the
REM   condition always matches the name. The ${date(...)} in the name is evaluated
REM   by SecureTransport, once per pull.
REM - triggerOnConditionEnabled switches on 'Trigger route execution based on
REM   condition'. The server refuses the condition without it.
REM - submitFilterType TRIGGER_FILE_CONTENT is 'Files read from trigger file
REM   content'. triggerFileOption fail means the run fails if a listed file is
REM   missing. Do not use retry here: it does not re-run the pull.
REM - The id is saved as AR_ID_SUBSCRIPTION for the later steps.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET BODY_FILE=%TEMP%\ar_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='AdvancedRouting'; application=$env:AR_APPLICATION; account=$env:AR_TEST_ACCOUNT; folder=$env:AR_SUBSCRIPTION_FOLDER; transferConfigurations=@(@{ tag='PARTNER-IN'; outbound=$false; site=$env:AR_PULL_SITE }); createFilesList=@{ createFilesListEnabled=$true; createFilesListFilename=$env:AR_TRIGGER_FILE_NAME }; postTransmissionActions=@{ submitFilterType='TRIGGER_FILE_CONTENT'; triggerFileOption='fail'; triggerOnConditionEnabled=$true; triggerOnConditionExpression=$env:AR_TRIGGER_CONDITION } } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the subscription on %AR_SUBSCRIPTION_FOLDER%...
CALL "%~dp0..\lib\post_admin.bat" subscriptions "%BODY_FILE%" AR_ID_SUBSCRIPTION
SET POST_RESULT=%ERRORLEVEL%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %POST_RESULT%
