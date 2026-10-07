@echo off
REM ==============================================================================
REM Script Name: 02.certificates_POST_generate.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script generates a new certificate on the server, using the
REM `/certificates` endpoint: the server creates the key pair and signs the
REM certificate with its own certificate authority (CA).
REM
REM Usage:
REM 02.certificates_POST_generate.bat [DAYS]
REM
REM   DAYS  how many days the certificate is valid (default 365)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It generates example_cert, a local x509 certificate - one the server itself
REM   uses, for example for a TLS listener. usage private with account set makes
REM   an account's own key pair instead.
REM - caPassword is the password of the server's CA, which signs the
REM   certificate: any other value answers 400 "Specify a valid CA Password."
REM   CA_PASSWORD is read from the environment, so set it first:
REM     SET CA_PASSWORD=the CA password
REM - Confirmed directly: the answer is 201 multipart/mixed, the certificate's
REM   JSON in its first part; the new id is also in the Location header, which is
REM   where this script reads it.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET NAME=example_cert
SET DAYS=%~1
IF "%DAYS%"=="" SET DAYS=365
ECHO %DAYS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo DAYS must be a whole number: %DAYS%
    EXIT /B 2
)
IF "%CA_PASSWORD%"=="" (
    echo Set CA_PASSWORD to the password of the server's certificate authority first.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\cert_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\cert_headers_%RANDOM%.txt

powershell -NoProfile -Command "@{ name=$env:NAME; type='x509'; usage='local'; subject=('CN=' + $env:NAME + ',O=Example'); keySize=2048; signAlgorithm='SHA256withRSA'; validityPeriod=[int]$env:DAYS; caPassword=$env:CA_PASSWORD } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Generating %NAME%, valid %DAYS% days...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$l = Select-String -Path $env:HEADERS_FILE -Pattern '^location:' | Select-Object -First 1; if ($l) { ($l.Line.Trim() -split '/')[-1] }"') DO echo The new certificate's id: %%I
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
