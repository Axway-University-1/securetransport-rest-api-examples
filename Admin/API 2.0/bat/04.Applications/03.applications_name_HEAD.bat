@echo off
REM ==============================================================================
REM Script Name: 03.applications_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks if an application exists using the `/applications/{name}` endpoint.
REM It demonstrates:
REM - A HEAD request to verify existence of an application by name, with the name URL-encoded
REM - Conditional logic based on the HTTP response code
REM
REM Usage:
REM 03.applications_name_HEAD.bat [NAME]
REM
REM   NAME  the application (default example_filepurge, one of the two 02.applications_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Application names with spaces must be URL-encoded: the script does it with jq (a space is %20).
REM - Run 02.applications_POST.bat first, or the answer is "does not exist". On a server that already has an AccountFilePurge application, 02 does not create example_filepurge
REM   (only one is allowed): check example_humansystem instead.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM - Confirmed directly: 200 when the application exists and 404 when it does not, with no body; a name with a space is found by its %20 form.
REM - Exit codes: 0 when the application exists, 1 when it does not (404) or the server answers otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_filepurge
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
powershell -NoProfile -Command "'Check if application with the name ' + [char]39 + $env:NAME + [char]39 + ' exists...'"
SET RESPONSE_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C
echo HTTP %RESPONSE_CODE%
IF "%RESPONSE_CODE%"=="200" (
    echo Application exists.
    EXIT /B 0
)
IF "%RESPONSE_CODE%"=="404" (
    echo Application does not exist.
    EXIT /B 1
)
echo Could not tell whether the application exists.
EXIT /B 1
