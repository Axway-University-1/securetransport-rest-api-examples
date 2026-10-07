@echo off
REM ==============================================================================
REM Script Name: 13.certificates_requests_id_POST_complete.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script completes a certificate signing request, using the
REM `/certificates/requests/{id}` endpoint with POST: it uploads the
REM certificate the certificate authority signed, and the server pairs it with
REM the private key it kept. The result is a new certificate; the request is
REM gone.
REM
REM Usage:
REM 13.certificates_requests_id_POST_complete.bat SIGNED_CERT [REQUEST_ID]
REM
REM   SIGNED_CERT  the certificate the CA signed, PEM or DER
REM   REQUEST_ID  the request's id (default: the one request for
REM               CN=example_csr,O=Example, which 09 creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is named example_csr_cert (alias).
REM - Confirmed directly: the answer is 200 with the new certificate's JSON. A
REM   certificate signed by a CA the server does not trust is accepted, and reads
REM   "Not chained to a trusted root": import the CA as a trusted certificate
REM   first.
REM - 07.certificates_id_DELETE.bat example_csr_cert removes the certificate.
REM - PowerShell is used to look the id up and read the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET SIGNED_CERT=%~1
IF NOT EXIST "%SIGNED_CERT%" (
    echo Usage: 13.certificates_requests_id_POST_complete.bat SIGNED_CERT [REQUEST_ID]
    EXIT /B 2
)
SHIFT
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
SET RESPONSE_FILE=%TEMP%\csr_complete_%RANDOM%.json

echo Completing the request %REQUEST_ID% with %SIGNED_CERT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%REQUEST_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" -F "alias=example_csr_cert" -F "certificateFile=@%SIGNED_CERT%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$c = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The new certificate {0}, id {1}, expires {2}' -f $c.name, $c.id, $c.expirationTime"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
