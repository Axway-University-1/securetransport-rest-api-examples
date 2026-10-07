@echo off
REM ==============================================================================
REM Script Name: 12.certificates_requests_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a certificate signing request, using the
REM `/certificates/requests/{id}` endpoint.
REM
REM Usage:
REM 12.certificates_requests_id_GET.bat [REQUEST_ID]
REM
REM   REQUEST_ID  the request's id (default: the one request for
REM               CN=example_csr,O=Example, which 09 creates)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is the request's JSON only, never the CSR;
REM   asking for anything but JSON answers 406. Keep the CSR
REM   09.certificates_requests_POST.bat writes.
REM - PowerShell is used to look the id up, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET REQUEST_ID=%~1
IF NOT "%REQUEST_ID%"=="" GOTO have_id
SET LOOKUP_FILE=%TEMP%\csr_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "subject=CN=example_csr,O=Example" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result); if ($r.Count -eq 1) { $r[0].id }"') DO SET REQUEST_ID=%%I
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF "%REQUEST_ID%"=="" (
    echo No single request for CN=example_csr,O=Example; give the request's id.
    EXIT /B 1
)
:have_id

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%REQUEST_ID%" -H "accept: application/json" -H "%REFERER_HEADER%"
echo.
