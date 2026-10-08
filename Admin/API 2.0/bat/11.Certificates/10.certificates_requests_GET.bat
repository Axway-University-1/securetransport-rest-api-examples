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
REM   USAGE  local or private (default: both); anything else is refused with exit 2, nothing sent
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: with a filter, resultSet.totalCount still counts every
REM   request; returnCount, and the result, are the filtered ones.
REM - Confirmed directly: keySize reads 0 and signAlgorithm null, whatever the
REM   request was made with.
REM - PowerShell is used to print one request per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Confirmed directly: the lab does not check the usage= filter of this endpoint, so a text that is neither local nor private
REM   lists every request (200). The script refuses it first, because the same filter on /certificates answers a misleading
REM   403 "Insufficient permissions to perform the operation" (see 01.certificates_GET.bat).
REM - Exit codes: 0 when the answer is 200, 1 when it is not, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\csrs_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates/requests
SET USAGE=%~1
IF NOT "%~2"=="" GOTO usage
IF "%USAGE%"=="" GOTO usage_ok
IF "%USAGE%"=="local" GOTO usage_ok
IF "%USAGE%"=="private" GOTO usage_ok
GOTO usage
:usage_ok
SET "QUERY=fields=id,subject,usage,account"
IF NOT "%USAGE%"=="" SET "QUERY=%QUERY%&usage=%USAGE%"

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo The requests: id, subject, usage, account:
SET "URL=%MAIN_URL%?%QUERY%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($r in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($r) { $a = $r.account; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}  {3}' -f $r.id, $r.subject, $r.usage, $a } }"
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
echo Usage: 10.certificates_requests_GET.bat [local^|private]
EXIT /B 2
