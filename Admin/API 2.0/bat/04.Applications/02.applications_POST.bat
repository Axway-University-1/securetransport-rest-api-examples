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
REM - Creating a flow application (HumanSystem), named example_humansystem
REM - Checking for an application of a maintenance type first, since the server allows only one of each
REM - Creating a maintenance application (AccountFilePurge) with a detailed schema, named example_filepurge, with no schedule unless you ask for one
REM
REM Usage:
REM 02.applications_POST.bat [SCHEDULE]
REM
REM   SCHEDULE  none (default): the maintenance application is created with no schedule, so it never runs by itself
REM             once: it gets a ONCE schedule that starts tomorrow at 00:00 and deletes files then (see Notes)
REM
REM Risk: write - creates a flow application and a File Maintenance one that deletes files when it is scheduled (none unless asked)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The two applications are example_humansystem and example_filepurge, so running this bare changes nothing that matters. 07.applications_name_DELETE.bat removes them.
REM   The other scripts of this folder act on example_filepurge by default.
REM - WHAT THE MAINTENANCE APPLICATION DOES. An AccountFilePurge application is a File Maintenance job: according to the reference, `deleteFilesDays` is the retention period (files older
REM   than that many days are deleted), `pattern` the file names it considers (`*.txt` here) and `removeFolders` makes it remove the folders left empty. This one keeps 90 days, matches
REM   *.txt and removes empty folders. It acts on the accounts that subscribe to it, and this script subscribes none. With the default SCHEDULE (none) the `schedules` list is empty and it
REM   never runs by itself; with `once` it runs at 00:00 of tomorrow, in the server's time zone, and deletes what that retention and pattern say for the accounts that subscribed.
REM - Only one application of a given maintenance type is allowed per server. Confirmed directly: a second AccountFilePurge application is refused, with or without a schedule, 400
REM   "Application of type AccountFilePurge already exists. Only one instance of this type is allowed." The script therefore looks for one by type first (GET /applications?type=AccountFilePurge),
REM   says so and creates none when there is one, under any name. That is not an error (the exit code stays 0). The lab has one that is not ours, so the creation of example_filepurge was
REM   NOT seen on the lab: it is written from the reference and tested against a stub `curl`. The flow application has no such limit, and its creation was seen.
REM - Confirmed directly: a creation answers 201 with no body; a name that exists is 400 "An application with this name already exists." (not 409); a name with a space is accepted
REM   and addressed as %20. A flow application is created with only `type`, `name` and `notes`.
REM - PowerShell is used to build each body. A ONCE schedule needs a start date in the future, so it is computed from today rather than written in the file, in place of jq.
REM - Exit codes: 0 when everything asked for was created or skipped for the reason above, 1 when the server refuses a creation (the other is still tried), 2 when SCHEDULE is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET PURGE_NAME=example_filepurge
SET FLOW_NAME=example_humansystem
SET USAGE=Usage: 02.applications_POST.bat [SCHEDULE]   with SCHEDULE none, the default, or once
SET SCHEDULE=%~1
IF "%SCHEDULE%"=="" SET SCHEDULE=none
IF NOT "%~2"=="" GOTO usage
IF NOT "%SCHEDULE%"=="none" IF NOT "%SCHEDULE%"=="once" GOTO usage
SET FAILED=0
SET RESPONSE_FILE=%TEMP%\app_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\app_body_%RANDOM%.json

REM A flow application: only the type, the name and the notes
powershell -NoProfile -Command "$b = [ordered]@{ type = 'HumanSystem'; name = $env:FLOW_NAME; notes = 'This is a HumanSystem application' }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"
SET DESCRIPTION=a HumanSystem application
CALL :create_application

REM A maintenance application. Only one of each type is allowed on a server, so look for one by type first.
SET TYPE=AccountFilePurge
echo Looking for an application of type '%TYPE%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "type=%TYPE%" --data-urlencode "fields=name" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not look for it: HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
SET EXISTING=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; (@($r.result | Where-Object { $_ -ne $null } | ForEach-Object { $_.name }) -join ([char]44 + [char]32))"') DO SET EXISTING=%%N
IF DEFINED EXISTING (
    powershell -NoProfile -Command "'An application of type ' + [char]39 + $env:TYPE + [char]39 + ' exists already (' + $env:EXISTING + '): the server allows only one, so none was created.'"
) ELSE (
    CALL :create_purge
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %FAILED%

REM ------------------------------------------------------------------------------
REM Creates the maintenance application: a ONCE schedule needs a start date in the
REM future, so it is computed from today rather than written in the file
REM ------------------------------------------------------------------------------
:create_purge
powershell -NoProfile -Command "$s = @(); if ($env:SCHEDULE -eq 'once') { $d = (Get-Date).ToUniversalTime().AddDays(1).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) + 'T00:00:00Z'; $s = @([ordered]@{ tag = $env:TYPE; type = 'ONCE'; executionTimes = @('00:00'); startDate = $d; skipHolidays = $false }) }; $b = [ordered]@{ type = $env:TYPE; name = $env:PURGE_NAME; notes = 'This is an ' + $env:TYPE + ' application'; deleteFilesDays = 90; pattern = '*.txt'; expirationPeriod = $true; removeFolders = $true; notifyDays = '90'; sendSentinelAlert = $false; warnNotifyAccount = $false; deletionNotifications = $false; deletionNotifyAccount = $false; schedules = $s }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 10))"
SET DESCRIPTION=an %TYPE% application (%PURGE_NAME%, schedule %SCHEDULE%)
CALL :create_application
EXIT /B 0

REM ------------------------------------------------------------------------------
REM POSTs the body in BODY_FILE and says what it creates; sets FAILED when the server refuses
REM ------------------------------------------------------------------------------
:create_application
echo Creating %DESCRIPTION%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
)
EXIT /B 0
:usage
echo %USAGE%
EXIT /B 2
