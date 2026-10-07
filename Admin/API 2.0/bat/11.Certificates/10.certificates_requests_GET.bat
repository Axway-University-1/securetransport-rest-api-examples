@echo off
REM ==============================================================================
REM Script Name: 10.certificates_requests_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the certificate signing requests waiting on the server,
REM using the `/certificates/requests` endpoint.
REM
REM Usage:
REM 10.certificates_requests_GET.bat [USAGE]
REM
REM   USAGE  local or private (default: both)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: with a filter, resultSet.totalCount still counts every
REM   request; returnCount, and the result, are the filtered ones.
REM - Confirmed directly: keySize reads 0 and signAlgorithm null, whatever the
REM   request was made with.
REM - PowerShell is used to print one request per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET USAGE=%~1
SET QUERY=fields=id,subject,usage,account
IF NOT "%USAGE%"=="" SET QUERY=%QUERY%^&usage=%USAGE%
SET RESPONSE_FILE=%TEMP%\csrs_%RANDOM%.json

echo The requests: id, subject, usage, account:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?%QUERY%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($r in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { $a = $r.account; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}  {3}' -f $r.id, $r.subject, $r.usage, $a }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
