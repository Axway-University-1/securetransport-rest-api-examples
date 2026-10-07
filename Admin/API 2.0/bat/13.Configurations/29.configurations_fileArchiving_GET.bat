@echo off
REM ==============================================================================
REM Script Name: 29.configurations_fileArchiving_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the file archiving settings, using the
REM `/configurations/fileArchiving` endpoint: whether the files transferred are
REM kept in an archive, where, encrypted with which certificate, and for how long.
REM
REM Usage:
REM 29.configurations_fileArchiving_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The archive can be a folder or an S3 bucket (isS3Storage and the s3*
REM   settings).
REM - PowerShell is used to print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/fileArchiving" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $to = if ($r.isS3Storage) { 'S3 bucket ' + $r.s3BucketName } else { $r.archiveFolder }; '  archiving: {0}, to {1}' -f $r.globalArchivingPolicy, $to; '  files deleted after {0} {1}, files up to {2} MB archived' -f $r.deleteFilesOlderThan, $r.deleteFilesOlderThanUnit, $r.maximumFileSizeAllowedToArchive"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
