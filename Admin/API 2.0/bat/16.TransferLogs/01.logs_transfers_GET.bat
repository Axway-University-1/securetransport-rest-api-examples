@echo off
REM ==============================================================================
REM Script Name: 01.logs_transfers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the transfer log, what File Tracking shows, using the
REM `/logs/transfers` endpoint. It demonstrates:
REM - Filtering the log by account
REM - Counting the matches with resultSet.totalCount, while limit keeps the
REM   response itself small
REM - Filtering by status as well
REM
REM Usage:
REM 01.logs_transfers_GET.bat [ACCOUNT]
REM
REM   ACCOUNT  the account whose transfers to read (default john)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account is filtered with account=. The endpoint ignores accountName=
REM   without a word and answers for every account (confirmed directly).
REM - resultSet.returnCount is the number of entries in this response, so it is
REM   never more than limit. resultSet.totalCount is the number of entries that
REM   match, however many were returned.
REM - curl -G sends the --data-urlencode values in the query string, encoded.
REM - PowerShell is used to read the response, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json

echo The 10 latest transfers of '%ACCOUNT%'...
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
  --data-urlencode "account=%ACCOUNT%" --data-urlencode "limit=10" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $j.result | ConvertTo-Json -Depth 10; '{0} transfer(s) of ''{1}'' in the log, in all.' -f $j.resultSet.totalCount, $env:ACCOUNT"

echo.
echo How many of them failed...
curl -s -k -G -u "%ST_USER%:%ST_PASSWORD%" "https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers" ^
  --data-urlencode "account=%ACCOUNT%" --data-urlencode "status=Failed" ^
  --data-urlencode "limit=1" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET FAILED_COUNT=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET FAILED_COUNT=%%N
IF "%FAILED_COUNT%"=="" SET FAILED_COUNT=An unknown number of
echo %FAILED_COUNT% failed transfer(s).

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
