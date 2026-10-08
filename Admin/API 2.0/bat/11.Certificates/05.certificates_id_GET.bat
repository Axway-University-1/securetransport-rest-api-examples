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
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
REM - Confirmed directly: with includePath=true the answer is an array, the
REM   certificate first and then each certificate above it.
REM - The same GET with "accept: multipart/mixed" exports the file as well;
REM   08.certificates_id_operations_POST_export.bat is the simpler way.
REM - PowerShell is used to read the id and print the summary, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\cert_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_cert
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "name=%NAME%" --data-urlencode "fields=id"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET CERT_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result); if ($r.Count -eq 1) { '1 ' + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CERT_ID=%%B
)
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% certificates named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

SET "URL=%MAIN_URL%/%CERT_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
SET "URL=%MAIN_URL%/%CERT_ID%?fingerprintAlgorithm=SHA256&base64EncodedFingerprint=true&fields=fingerprint"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%F IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).fingerprint"') DO echo Its SHA256 fingerprint: %%F

echo.
echo Its path, from the certificate up:
SET "URL=%MAIN_URL%/%CERT_ID%?includePath=true&fields=name,subject"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($c in @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json)) { '  {0}  {1}' -f $c.name, $c.subject }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 05.certificates_id_GET.bat [NAME]
EXIT /B 2
