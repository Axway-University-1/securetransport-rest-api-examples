@echo off
REM ==============================================================================
REM Script Name: 04.applications_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves information about a specific application using the
REM `/applications/{name}` endpoint. It also checks whether business units are
REM assigned to the application.
REM
REM Usage:
REM 04.applications_name_GET.bat [NAME]
REM
REM   NAME  the application (default example_filepurge, one of the two 02.applications_POST.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Application names with spaces must be URL-encoded: the script does it with jq.
REM - On a server that already has an AccountFilePurge application, 02 does not create example_filepurge (only one is allowed): read example_humansystem instead.
REM - PowerShell is used to URL-encode the name and read the business units, in place of jq.
REM - Confirmed directly: a flow application (HumanSystem) answers its type, id, name, notes, managedByCG, additionalAttributes and businessUnits and no `schedules`; a maintenance
REM   application (read here only on an ArchiveMaint example) also answers `schedules`, with `startDate` as the epoch in milliseconds, written as text.
REM - Exit codes: 0 when the server answered 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_filepurge
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\app_response_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
TYPE "%RESPONSE_FILE%"
echo.
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

SET NUMBER_OF_ASSIGNED_BU=0
FOR /F %%R IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).businessUnits | Where-Object { $_ -ne $null }).Count"') DO SET NUMBER_OF_ASSIGNED_BU=%%R

IF "%NUMBER_OF_ASSIGNED_BU%"=="0" (
    echo No business units assigned to the application.
) ELSE (
    powershell -NoProfile -Command "Write-Output 'Business units assigned to the application:'; (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).businessUnits"
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
