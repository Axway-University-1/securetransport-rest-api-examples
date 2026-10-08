@echo off
REM ==============================================================================
REM Script Name: 45.configurations_storageProfiles_options_PUT_register.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds an S3 storage profile, example_s3: a bucket the server can
REM keep files in, named by account home folders, sites and business units.
REM There is no storage profile resource; a profile is Server Configuration
REM Options, set here with the `/configurations/options` endpoint and PUT.
REM
REM Usage:
REM 45.configurations_storageProfiles_options_PUT_register.bat BUCKET [REGION [ENDPOINT]]
REM
REM   BUCKET    the bucket
REM   REGION    its region (default us-east-1)
REM   ENDPOINT  an S3-compatible service's address, for example
REM             http://s3.example.com:9000 (default: AWS itself)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - S3_ACCESS_KEY and S3_SECRET_KEY are read from the environment; leave them
REM   unset to use the AWS default credentials of the server.
REM - It adds example_s3 to the option StorageProfiles.S3.Registry, which
REM   creates the profile's own options, StorageProfiles.S3.Registry.example_s3.*
REM   (Bucket, Region, CustomEndpointUrl, AccessKey, SecretKey, ...), then sets
REM   them.
REM - Confirmed directly: saving the profile tests the connection: a bucket the
REM   server cannot reach answers 400 "Connection to S3 storage using supplied
REM   setting failed" and nothing is saved.
REM - 47.configurations_storageProfiles_options_PUT_unregister.bat removes it.
REM - tests/integration/lib/dummy_servers.py has a FakeS3 that can stand in for an
REM   S3 bucket to try these examples against.
REM - PowerShell is used to read the registry and build the bodies, in place of jq.
REM - The registry is read first, and the script stops (exit 1) when it cannot be read: sending a registry made of this one profile alone would drop the
REM   others. Confirmed directly: when the settings of the profile are then refused (400, a bucket that cannot be reached), the name is in the registry all the
REM   same, with every one of its options empty: the script says so, and 47.configurations_storageProfiles_options_PUT_unregister.bat takes it out.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET "BUCKET=%~1"
SET "REGION=%~2"
IF "%REGION%"=="" SET REGION=us-east-1
SET "ENDPOINT=%~3"
SET PROFILE=example_s3
SET REGISTRY_OPTION=StorageProfiles.S3.Registry
IF "%BUCKET%"=="" (
    echo Usage: 45.configurations_storageProfiles_options_PUT_register.bat BUCKET [REGION [ENDPOINT]]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

REM The profiles already registered, plus this one. Nothing is sent when the registry cannot be read: a registry of this profile alone would drop the others
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/options/%REGISTRY_OPTION%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the registry of storage profiles ^(HTTP %HTTP_CODE%^), so nothing was changed.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $v = @(@($r.values | Where-Object { $_ }) + $env:PROFILE | Sort-Object -Unique); 'Registering {0}; the registry becomes {1}' -f $env:PROFILE, (ConvertTo-Json -Compress -InputObject $v); ConvertTo-Json -Compress -Depth 5 -InputObject @([ordered]@{ name=$env:REGISTRY_OPTION; values=$v }) | Set-Content -Encoding ASCII $env:BODY_FILE"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/options" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "$p = $env:REGISTRY_OPTION + '.' + $env:PROFILE; ConvertTo-Json -Compress -Depth 5 -InputObject @(@{ name=$p + '.Bucket'; values=@($env:BUCKET) }, @{ name=$p + '.Region'; values=@($env:REGION) }, @{ name=$p + '.CustomEndpointUrl'; values=@([string]$env:ENDPOINT) }, @{ name=$p + '.AccessKey'; values=@([string]$env:S3_ACCESS_KEY) }, @{ name=$p + '.SecretKey'; values=@([string]$env:S3_SECRET_KEY) }) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Setting its bucket %BUCKET%, region %REGION% %ENDPOINT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/options" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    echo %PROFILE% is in the registry all the same, without its settings: 47.configurations_storageProfiles_options_PUT_unregister.bat removes it.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
