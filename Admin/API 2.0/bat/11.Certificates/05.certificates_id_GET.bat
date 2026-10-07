@echo off
REM ==============================================================================
REM Script Name: 05.certificates_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a certificate, using the `/certificates/{id}` endpoint.
REM It demonstrates:
REM - The whole certificate, as JSON
REM - Its SHA256 fingerprint, base64 encoded, with fingerprintAlgorithm=
REM - Its path to the root, with includePath=true
REM
REM Usage:
REM 05.certificates_id_GET.bat [NAME]
REM
REM   NAME  the certificate's name (default example_cert)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
REM - Confirmed directly: with includePath=true the answer is an array, the
REM   certificate first and then each certificate above it.
REM - The same GET with "accept: multipart/mixed" exports the file as well;
REM   08.certificates_id_operations_POST_export.bat is the simpler way.
REM - PowerShell is used to read the id and print the summary, in place of jq.
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
SET RESPONSE_FILE=%TEMP%\cert_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%CERT_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"

echo.
echo.
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET ^
  "%MAIN_URL%/%CERT_ID%?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%F IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).fingerprint"') DO echo Its SHA256 fingerprint: %%F

echo.
echo Its path, from the certificate up:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%CERT_ID%?includePath=true&fields=name,subject" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($c in @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json)) { '  {0}  {1}' -f $c.name, $c.subject }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
