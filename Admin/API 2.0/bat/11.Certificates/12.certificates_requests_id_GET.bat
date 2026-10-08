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
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is the request's JSON only, never the CSR;
REM   asking for anything but JSON answers 406. Keep the CSR
REM   09.certificates_requests_POST.bat writes.
REM - PowerShell is used to look the id up, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\csr_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET REQUEST_ID=%~1
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
IF NOT "%REQUEST_ID%"=="" GOTO have_id
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "subject=CN=example_csr,O=Example"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result); if ($r.Count -eq 1) { $r[0].id }"') DO SET REQUEST_ID=%%I
IF "%REQUEST_ID%"=="" (
    echo No single request for CN=example_csr,O=Example; give the request's id.
    EXIT /B 1
)
:have_id

SET "URL=%MAIN_URL%/%REQUEST_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"
echo.
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
echo Usage: 12.certificates_requests_id_GET.bat [REQUEST_ID]
EXIT /B 2
