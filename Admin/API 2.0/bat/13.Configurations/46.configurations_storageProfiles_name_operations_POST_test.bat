@echo off
REM ==============================================================================
REM Script Name: 46.configurations_storageProfiles_name_operations_POST_test.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests an S3 storage profile, using the
REM `/configurations/storageProfiles/{storageProfile}/operations` endpoint with
REM operation=test: the server connects to the bucket with the profile's saved
REM settings.
REM
REM Usage:
REM 46.configurations_storageProfiles_name_operations_POST_test.bat [PROFILE]
REM
REM   PROFILE  the storage profile (default example_s3)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a working profile answers 204; the server asks for the
REM   bucket (HEAD /<bucket>). An unknown profile answers 404 "Storage profile
REM   ... not found."
REM - tests/integration/lib/dummy_servers.py has a FakeS3 that can stand in for an
REM   S3 bucket to try these examples against.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PROFILE=%~1
IF "%PROFILE%"=="" SET PROFILE=example_s3
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=

echo Testing the storage profile %PROFILE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/storageProfiles/%PROFILE%/operations?operation=test" -H "accept: */*" -H "%REFERER_HEADER%"'') DO SET HTTP_CODE=%%C
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
echo The bucket can be reached.
