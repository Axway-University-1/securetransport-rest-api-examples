@echo off
REM ==============================================================================
REM Script Name: 06.applications_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs partial updates to an application using the
REM `/applications/{name}` endpoint with the PATCH method.
REM It demonstrates:
REM - Updating the notes field
REM - Updating the startDate of the first schedule, when the application has one
REM
REM Usage:
REM 06.applications_name_PATCH.bat [NAME]
REM
REM   NAME  the application (default example_filepurge, one of the two 02.applications_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PATCH allows partial updates without replacing the entire object.
REM - It first reads the application and prints the old notes and, when there is one, the first schedule's start date (as an ISO date, ready to be sent back), then the body that undoes
REM   each change. The new start date is the day after tomorrow, 00:00 UTC: a ONCE schedule needs a date in the future.
REM - An application with no schedule, such as example_humansystem or a File Maintenance application created with the default SCHEDULE none, has no `/schedules/0/startDate` to replace,
REM   so that patch is skipped and said so. Only the notes are patched.
REM - PowerShell is used to read the application and build each patch, in place of jq.
REM - Confirmed directly: each PATCH answers 204 with no body. Replacing `/schedules/0/startDate` works on an application that has a schedule (seen on an ArchiveMaint example, not on a
REM   File Maintenance one: the lab has one that is not ours) and the date reads back as milliseconds. A start date in the past, which is what this script used to send (2025-02-21),
REM   is 400 "startDate occurs before the current moment."; on an application with no schedules the path is 400 `Missing field "schedules"`.
REM - Confirmed directly (on an ArchiveMaint example with a ONCE schedule): the server derives the schedule's `executionTimes` from the time of day of the start date in its own time
REM   zone. This one is at +03:00: a start date of 00:00:00Z was read back with `executionTimes` ["03:00"], and the old start date, sent back as the ISO date this script prints, restored
REM   both, compared exactly. A PUT that sends the application back as it was read, the start date still the milliseconds, is 204 and changes nothing.
REM - Exit codes: 0 when every patch sent was answered 204, 1 when the application cannot be read or the server refuses a patch (the later one is not sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_filepurge
IF NOT "%~2"=="" (
    echo Usage: 06.applications_name_PATCH.bat [NAME]
    EXIT /B 2
)
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET APP_URL=%MAIN_URL%/%NAME_URI%
SET RESPONSE_FILE=%TEMP%\app_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\app_body_%RANDOM%.json

echo Getting the application %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%APP_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the application %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
REM The server answers a start date as the epoch in milliseconds, in text; turn it into a date that can be sent back
SET OLD_START=
SET START_FILE=%TEMP%\app_start_%RANDOM%.txt
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $s = @($o.schedules | Where-Object { $_ -ne $null }); $out = ''; if ($s.Count -gt 0) { $d = [string]$s[0].startDate; if ($d -match '^[0-9]+$') { $out = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$d).UtcDateTime.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) } else { $out = $d } }; [IO.File]::WriteAllText($env:START_FILE, $out)"
SET /P OLD_START=<"%START_FILE%"
IF EXIST "%START_FILE%" DEL "%START_FILE%"
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The notes of {0} are now {1}{2}{1}.' -f $env:NAME, [char]39, $o.notes; $b = ConvertTo-Json -InputObject @([ordered]@{ op = 'replace'; path = '/notes'; value = [string]$o.notes }) -Compress; 'To put them back, PATCH this body: ' + $b"
IF DEFINED OLD_START (
    echo The start date of the first schedule is now %OLD_START%.
    powershell -NoProfile -Command "'To put it back, PATCH this body: ' + (ConvertTo-Json -InputObject @([ordered]@{ op = 'replace'; path = '/schedules/0/startDate'; value = $env:OLD_START }) -Compress)"
)

powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/notes'; value = 'Patched note' }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"
CALL :patch "Patching the application to change the notes"
IF ERRORLEVEL 1 EXIT /B 1

IF DEFINED OLD_START (
    REM A start date has to be in the future: the day after tomorrow, 00:00 UTC
    powershell -NoProfile -Command "$d = (Get-Date).ToUniversalTime().AddDays(2).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture) + 'T00:00:00Z'; $op = [ordered]@{ op = 'replace'; path = '/schedules/0/startDate'; value = $d }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"
    CALL :patch "Patching the application to change the startDate"
    IF ERRORLEVEL 1 EXIT /B 1
) ELSE (
    echo The application has no schedule, so there is no startDate to change.
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Sends the patch in BODY_FILE and says %~1; exit 1 when the server does not answer 204
REM ------------------------------------------------------------------------------
:patch
echo %~1...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%APP_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="204" EXIT /B 0
CALL :show_error
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 1

:show_error
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
