@echo off
REM ==============================================================================
REM Script Name: 05.applications_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script updates an application using the `/applications/{name}` endpoint.
REM It demonstrates:
REM - Retrieving the full application object
REM - Modifying the notes field (by default with a timestamp)
REM - Sending a PUT request to update the application
REM
REM Usage:
REM 05.applications_name_PUT.bat [NAME [NOTES]]
REM
REM   NAME   the application (default example_filepurge, one of the two 02.applications_POST.bat creates)
REM   NOTES  the new notes (default "New note" and the time, in UTC); "" for none
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PUT replaces the entire object, so all required fields must be preserved: the script sends back the object it read, with only the notes changed.
REM - It prints the old notes, and the command that puts them back, before it changes anything.
REM - PowerShell is used to is used to edit the retrieved JSON. No file is written: the answer is kept in a variable, in place of jq.
REM - On a server that already has an AccountFilePurge application, 02 does not create example_filepurge (only one is allowed): use example_humansystem.
REM - Confirmed directly: a success is 204 with no body (also for a flow application sent back as it was read); the new notes read back at once.
REM - Exit codes: 0 when the server answered 204, 1 when the application cannot be read or the server refuses, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_filepurge
IF NOT "%~3"=="" (
    echo Usage: 05.applications_name_PUT.bat [NAME [NOTES]]
    EXIT /B 2
)
SET "NEW_NOTES=%~2"
SET NOTES_GIVEN=
IF NOT [%2]==[] SET NOTES_GIVEN=yes
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\app_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\app_body_%RANDOM%.json

echo Getting the application %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the application %NAME%: HTTP %HTTP_CODE%
    GOTO refused
)
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The notes of {0} are now {1}{2}{1}.' -f $env:NAME, [char]39, $o.notes; 'To put them back: 05.applications_name_PUT.bat {0} {1}{2}{1}' -f $env:NAME, [char]34, $o.notes"

REM
REM Edit the retrieved object as an object rather than as text. This targets the
REM notes field itself and always produces valid JSON, which a regular
REM expression substitution cannot guarantee.
REM
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $o.notes = if ($env:NOTES_GIVEN -eq 'yes') { [string]$env:NEW_NOTES } else { 'New note ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) }; [IO.File]::WriteAllText($env:BODY_FILE, ($o | ConvertTo-Json -Depth 100 -Compress))"

echo Changing the notes...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" GOTO refused
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
