@echo off
REM ==============================================================================
REM Script Name: 09.certificates_requests_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script generates a certificate signing request (CSR) on the server,
REM using the `/certificates/requests` endpoint. The server keeps the private
REM key; the CSR goes to a certificate authority, and the certificate it signs
REM comes back with 13.certificates_requests_id_POST_complete.bat.
REM
REM Usage:
REM 09.certificates_requests_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The request is for CN=example_csr,O=Example, a local certificate - one the
REM   server itself uses. usage private, with account, is for an account's key.
REM - The CSR is written to example_csr.req, in the current folder.
REM - Confirmed directly: the answer is 201 multipart/mixed, the request's JSON
REM   then the CSR. That is the only place the CSR is: a GET of the request
REM   answers its JSON alone.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET OUTPUT=example_csr.req
SET RESPONSE_FILE=%TEMP%\csr_%RANDOM%.txt

echo Generating a request for CN=example_csr,O=Example...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "{\"subject\":\"CN=example_csr,O=Example\",\"usage\":\"local\",\"keySize\":2048,\"signAlgorithm\":\"SHA256withRSA\"}"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

REM The JSON part holds the id; the second part is the CSR itself
powershell -NoProfile -Command "$t = Get-Content -Raw $env:RESPONSE_FILE; $m = [regex]::Match($t, '-----BEGIN CERTIFICATE REQUEST-----[\s\S]*?-----END CERTIFICATE REQUEST-----'); Set-Content -Encoding ASCII -Path $env:OUTPUT -Value ($m.Value -replace \"`r\", ''); 'The request''s id: ' + [regex]::Match($t, '\"id\" *: *\"([^\"]*)\"').Groups[1].Value"
echo Wrote the CSR to %OUTPUT%; send it to your certificate authority.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
