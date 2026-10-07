@echo off
REM ==============================================================================
REM Script Name: 03.certificates_POST_import_partner.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script imports a partner's certificate for an account, using the
REM `/certificates` endpoint with a multipart/mixed body: the certificate's JSON
REM in the first part, the certificate file in the second. The account then
REM trusts the partner, for example to verify or encrypt files with it.
REM
REM Usage:
REM 03.certificates_POST_import_partner.bat ACCOUNT CERT_FILE
REM
REM   ACCOUNT    the account the partner certificate belongs to
REM   CERT_FILE  the partner's certificate, PEM or DER, for example the
REM              example_cert.pem 08.certificates_id_operations_POST_export.bat
REM              writes
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It imports the certificate as example_partner.
REM - Confirmed directly: an import answers 200 with the certificate's JSON, not
REM   the 201 a generate answers.
REM - Deleting the account deletes its certificates too.
REM - A private key is imported as a PKCS#12 file with usage private, its
REM   password in password; see the API reference.
REM - PowerShell is used to build the JSON part and read the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET ACCOUNT=%~1
SET CERT_FILE=%~2
IF "%ACCOUNT%"=="" GOTO usage
IF NOT EXIST "%CERT_FILE%" GOTO usage
SET BODY_FILE=%TEMP%\cert_import_%RANDOM%.bin
SET RESPONSE_FILE=%TEMP%\cert_import_response_%RANDOM%.json

REM The multipart/mixed body: the JSON part, then the file part
powershell -NoProfile -Command "$json = @{ name='example_partner'; type='x509'; usage='partner'; account=$env:ACCOUNT } | ConvertTo-Json -Compress; $enc = [Text.Encoding]::ASCII; $head = $enc.GetBytes(\"--BOUNDARY`r`nContent-Type: application/json`r`n`r`n$json`r`n--BOUNDARY`r`nContent-Type: application/octet-stream`r`n`r`n\"); $tail = $enc.GetBytes(\"`r`n--BOUNDARY--`r`n\"); [IO.File]::WriteAllBytes($env:BODY_FILE, $head + [IO.File]::ReadAllBytes((Resolve-Path $env:CERT_FILE)) + $tail)"

echo Importing %CERT_FILE% as example_partner for %ACCOUNT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: multipart/mixed; boundary=BOUNDARY" --data-binary "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="200" IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$c = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Imported {0}, id {1}, subject {2}, expires {3}' -f $c.name, $c.id, $c.subject, $c.expirationTime"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
GOTO :EOF

:usage
echo Usage: 03.certificates_POST_import_partner.bat ACCOUNT CERT_FILE
EXIT /B 2
