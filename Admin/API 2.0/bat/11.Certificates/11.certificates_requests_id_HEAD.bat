@echo off
REM ==============================================================================
REM Script Name: 11.certificates_requests_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a certificate signing request exists, using the
REM `/certificates/requests/{id}` endpoint with HEAD: 200 when it does, 404
REM when it does not.
REM
REM Usage:
REM 11.certificates_requests_id_HEAD.bat [REQUEST_ID]
REM
REM   REQUEST_ID  the request's id (default: the one request for
REM               CN=example_csr,O=Example, which 09 creates)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a completed request is gone, 404.
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

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%REQUEST_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The request %REQUEST_ID% exists.
) ELSE (
    echo The request %REQUEST_ID% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
