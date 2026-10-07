@echo off
REM ==============================================================================
REM Script Name: 08.certificates_id_operations_POST_export.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script exports a certificate to a file, using the
REM `/certificates/{id}/operations` endpoint with operation=export: PEM, DER
REM (crt), or PKCS#12 with its private key.
REM
REM Usage:
REM 08.certificates_id_operations_POST_export.bat [NAME [FORMAT]]
REM
REM   NAME    the certificate's name (default example_cert)
REM   FORMAT  pem, crt or pkcs12 (default pem)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
REM - The file is NAME.pem, NAME.crt or NAME.p12, in the current folder.
REM - pkcs12 holds the private key too, encrypted with EXPORT_PASSWORD, read from
REM   the environment: SET EXPORT_PASSWORD=a password first. It is chosen
REM   freely; nothing checks it.
REM - Confirmed directly: the body must be a multipart form, even for pem and
REM   crt, whose exportPassword may be empty. Without one: 400 "Entity is
REM   empty." includePath=true adds the certificates above it to a pem.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_cert
SET FORMAT=%~2
IF "%FORMAT%"=="" SET FORMAT=pem
SET EXTENSION=
IF "%FORMAT%"=="pem" SET EXTENSION=pem
IF "%FORMAT%"=="crt" SET EXTENSION=crt
IF "%FORMAT%"=="pkcs12" SET EXTENSION=p12
IF "%EXTENSION%"=="" (
    echo FORMAT is pem, crt or pkcs12, not %FORMAT%.
    EXIT /B 2
)
IF "%FORMAT%"=="pkcs12" IF "%EXPORT_PASSWORD%"=="" (
    echo Set EXPORT_PASSWORD first: it protects the private key.
    EXIT /B 2
)
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
SET OUTPUT=%NAME%.%EXTENSION%

echo Exporting %NAME% as %FORMAT% to %OUTPUT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%OUTPUT%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%CERT_ID%/operations?operation=export&format=%FORMAT%" -H "accept: application/octet-stream" -H "%REFERER_HEADER%" -F "exportPassword=%EXPORT_PASSWORD%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    TYPE "%OUTPUT%"
    echo.
    DEL "%OUTPUT%"
    EXIT /B 1
)
FOR %%A IN ("%OUTPUT%") DO echo Wrote %OUTPUT%, %%~zA bytes.
