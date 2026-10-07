@echo off
REM ==============================================================================
REM Script Name: 02.applications_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates applications using the `/applications` endpoint.
REM It demonstrates:
REM - Checking for an existing application of a flow type
REM - Creating a flow application if not found
REM - Creating a maintenance application with a detailed schema
REM
REM Usage:
REM 02.applications_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Maintenance applications require specific schema fields.
REM - Only one application of a given maintenance type is allowed per server -
REM   confirmed against a real server, which rejected a second AccountFilePurge
REM   application with "Only one instance of this type is allowed." This script
REM   checks for one first, the same way it already does for the flow type
REM   above, rather than assuming the POST will succeed.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET FLOW_APPLICATIONS=AdvancedRouting,Basic,HumanSystem,MBFT,SharedFolder,SiteMailbox,StandardRouter
SET MAINTENANCE_APPLICATIONS=AccountFilePurge,AccountTTL,ArchiveMaint,AuditLogMaint,LogEntryMaint,LoginThresholdMaintenance,PackageRetentionMaint,SentinelLinkDataMaint,TransferLogMaint,UnlicensedAccountMaint

FOR /F "tokens=3 delims=," %%A IN ("%FLOW_APPLICATIONS%") DO SET RANDOM_APP=%%A
echo Get the name of an application of type '%RANDOM_APP%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications?fields=name&type=%RANDOM_APP%" -H "accept: application/json" -H "%REFERER_HEADER%" > app.json

FOR /F "delims=" %%B IN ('powershell -Command "(Get-Content app.json | ConvertFrom-Json).result[0].name"') DO SET NAME_OF_APP=%%B
echo Name of the application: %NAME_OF_APP%

IF "%NAME_OF_APP%"=="null" (
    echo No application of type '%RANDOM_APP%' found.
    echo Create an application of type '%RANDOM_APP%'...
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications" ^
    -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
    -d "{ \"type\": \"%RANDOM_APP%\", \"name\": \"%RANDOM_APP% Application\", \"notes\": \"This is a %RANDOM_APP% application\" }"
) ELSE (
    echo Application of type '%RANDOM_APP%' found.
)

FOR /F "tokens=1 delims=," %%C IN ("%MAINTENANCE_APPLICATIONS%") DO SET RANDOM_APP=%%C
echo Get an application of type '%RANDOM_APP%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications?fields=name&type=%RANDOM_APP%" -H "accept: application/json" -H "%REFERER_HEADER%" > app2.json

FOR /F "delims=" %%D IN ('powershell -Command "(Get-Content app2.json | ConvertFrom-Json).result[0].name"') DO SET NAME_OF_MAINT_APP=%%D
echo Name of the application: %NAME_OF_MAINT_APP%

IF "%NAME_OF_MAINT_APP%"=="null" (
    echo No application of type '%RANDOM_APP%' found.
    echo Create an application of type '%RANDOM_APP%'...
    REM A ONCE schedule needs a start date in the future, so this is computed
    REM relative to today rather than hardcoded to a date that will eventually
    REM be in the past.
    FOR /F "delims=" %%S IN ('powershell -Command "(Get-Date).AddDays(1).ToString(''yyyy-MM-ddT00:00:00Z'')"') DO SET START_DATE=%%S
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications" ^
    -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
    -d "{ \"type\": \"%RANDOM_APP%\", \"name\": \"%RANDOM_APP% Application\", \"notes\": \"This is a %RANDOM_APP% application\", \"deleteFilesDays\": 90, \"pattern\": \"*.txt\", \"expirationPeriod\": true, \"removeFolders\": true, \"notifyDays\": \"90\", \"sendSentinelAlert\": false, \"warnNotifyAccount\": false, \"deletionNotifications\": false, \"deletionNotifyAccount\": false, \"schedules\": [ { \"tag\": \"%RANDOM_APP%\", \"type\": \"ONCE\", \"executionTimes\": [\"00:00\"], \"startDate\": \"%START_DATE%\", \"skipHolidays\": false } ] }"
) ELSE (
    echo Application of type '%RANDOM_APP%' found.
)

IF EXIST app.json DEL app.json
IF EXIST app2.json DEL app2.json
