@echo off
REM ==============================================================================
REM Script Name: 08.configurations_options_groups_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one group of Server Configuration Options, using the
REM `/configurations/options/groups/{name}` endpoint: the UI schema of its
REM options, with each option's title and type.
REM
REM Usage:
REM 08.configurations_options_groups_name_GET.bat [GROUP]
REM
REM   GROUP  the group (default StorageProfiles.S3.Group)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: some groups the list returns answer 501 "Group with
REM   name ... not implemented" here, for example SMTP.Group.
REM - PowerShell is used to print the options, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET GROUP=%~1
IF "%GROUP%"=="" SET GROUP=StorageProfiles.S3.Group
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options/groups/%GROUP%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the group %GROUP% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $u = $r.uiSchema; '{0}: {1}' -f $u.title, $u.description; foreach ($p in $u.properties.PSObject.Properties) { $t = $p.Value.type; if (-not $t) { $t = '-' }; '  {0}  {1}  {2}' -f $p.Name, $t, $p.Value.title }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
