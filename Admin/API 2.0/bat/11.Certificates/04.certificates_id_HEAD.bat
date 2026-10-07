@echo off
REM ==============================================================================
REM Script Name: 04.certificates_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a certificate exists, using the
REM `/certificates/{id}` endpoint with HEAD: 200 when it does, 404 when it
REM does not.
REM
REM Usage:
REM 04.certificates_id_HEAD.bat [NAME]
REM
REM   NAME  the certificate's name (default example_cert)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
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

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%CERT_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The certificate %NAME% exists, id %CERT_ID%.
) ELSE (
    echo The certificate %NAME%, id %CERT_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
