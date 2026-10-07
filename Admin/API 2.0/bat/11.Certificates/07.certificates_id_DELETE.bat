@echo off
REM ==============================================================================
REM Script Name: 07.certificates_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a certificate, using the `/certificates/{id}` endpoint.
REM
REM Usage:
REM 07.certificates_id_DELETE.bat [NAME]
REM
REM   NAME  the certificate's name (default example_cert, which
REM         02.certificates_POST_generate.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
REM - Only ever point it at a certificate you created: a site, a listener or a
REM   partner may depend on it.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_cert
SET LOOKUP_FILE=%TEMP%\cert_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET CERT_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result); if ($r.Count -eq 1) { '1 ' + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CERT_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% certificates named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

echo Deleting the certificate %NAME%, id %CERT_ID%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%CERT_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
