@echo off
REM ==============================================================================
REM Script Name: 47.configurations_storageProfiles_options_PUT_unregister.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script removes the S3 storage profile example_s3, using the
REM `/configurations/options` endpoint with PUT: it takes example_s3 out of the
REM option StorageProfiles.S3.Registry, which removes the profile's own options.
REM
REM Usage:
REM 47.configurations_storageProfiles_options_PUT_unregister.bat
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The other profiles in the registry stay.
REM - Confirmed directly: an empty registry is set with [""]; an empty list
REM   answers 400 "Invalid argument length."
REM - PowerShell is used to read the registry, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PROFILE=example_s3
SET REGISTRY_OPTION=StorageProfiles.S3.Registry
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options/%REGISTRY_OPTION%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $v = @($r.values | Where-Object { $_ -and $_ -ne $env:PROFILE }); if ($v.Count -eq 0) { $v = @('') }; 'Removing {0}; the registry becomes {1}' -f $env:PROFILE, (ConvertTo-Json -Compress -InputObject $v); ConvertTo-Json -Compress -Depth 5 -InputObject @([ordered]@{ name=$env:REGISTRY_OPTION; values=$v }) | Set-Content -Encoding ASCII $env:BODY_FILE"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/options" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
