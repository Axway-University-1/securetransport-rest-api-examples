@echo off
REM ==============================================================================
REM Script Name: 07.applications_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes applications using the `/applications/{name}` endpoint.
REM For each application it first reads it, to say what it is about to delete, and deletes it if it exists.
REM
REM By default it cleans up the two applications created by 02.applications_POST.bat.
REM
REM Usage:
REM 07.applications_name_DELETE.bat [NAME...]
REM
REM   NAME  the applications to delete (default example_filepurge and example_humansystem, the ones 02.applications_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script deletes data. Application names with spaces must be URL-encoded: the script does it with jq.
REM - Only ever point this at names this folder's own POST script created. A server's built-in maintenance applications (Audit Log Maintenance, Transfer Log
REM   Maintenance and the others) are real housekeeping jobs, not test data, and the lab's own AccountFilePurge application is not ours either: any name can be given, so check it.
REM   Each application is read first and its type is printed, so that a wrong name shows before it is deleted.
REM - PowerShell is used to URL-encode each name and read the application, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an application that is not there is 404; an application that still has a subscription cannot be deleted (400 "has active subscriptions").
REM - Exit codes: 0 when every application named was deleted or was not there, 1 when the server refused one (the others are still tried), 2 when a name is empty (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET FAILED=0
SET RESPONSE_FILE=%TEMP%\app_response_%RANDOM%.json
IF [%1]==[] (
    FOR %%A IN (example_filepurge example_humansystem) DO CALL :delete_application "%%A"
    GOTO done
)
REM Nothing is sent until every name is known to be a name
SET ARGS_OK=yes
FOR %%A IN (%*) DO IF "%%~A"=="" SET ARGS_OK=
IF NOT "%ARGS_OK%"=="yes" (
    echo An application name must not be empty.
    echo Usage: 07.applications_name_DELETE.bat [NAME...]
    EXIT /B 2
)
FOR %%A IN (%*) DO CALL :delete_application "%%~A"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %FAILED%

REM ------------------------------------------------------------------------------
REM Reads the application named in %1, says what it is, and deletes it if it exists
REM ------------------------------------------------------------------------------
:delete_application
SET APP_TO_DELETE=%~1
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:APP_TO_DELETE)"') DO SET NAME_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%NAME_URI%" --data-urlencode "fields=type" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="404" (
    powershell -NoProfile -Command "'Application ' + $env:APP_TO_DELETE + ' does not exist.'"
    EXIT /B 0
)
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the application: HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
    EXIT /B 0
)
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Application exists. Deleting application ' + [char]39 + $env:APP_TO_DELETE + [char]39 + ' (type ' + $a.type + ')...'"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
)
EXIT /B 0
