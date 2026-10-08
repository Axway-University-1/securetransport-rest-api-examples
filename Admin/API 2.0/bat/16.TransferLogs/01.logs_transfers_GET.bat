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
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account is filtered with account=. The endpoint ignores accountName=
REM   without a word and answers for every account (confirmed directly).
REM - resultSet.returnCount is the number of entries in this response, so it is
REM   never more than limit. resultSet.totalCount is the number of entries that
REM   match, however many were returned.
REM - curl -G sends the --data-urlencode values in the query string, encoded.
REM - PowerShell is used to read the count, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when both answers are 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/transfers

SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo The 10 latest transfers of '%ACCOUNT%'...
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "account=%ACCOUNT%" --data-urlencode "sortByStartTime=descending" --data-urlencode "limit=10"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $j.result | ConvertTo-Json -Depth 10; '{0} transfer(s) of ''{1}'' in the log, in all.' -f $j.resultSet.totalCount, $env:ACCOUNT"

echo.
echo How many of them failed...
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "account=%ACCOUNT%" --data-urlencode "status=Failed" --data-urlencode "limit=1" --data-urlencode "fields=id"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET FAILED_COUNT=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount } catch { }"') DO SET FAILED_COUNT=%%N
IF "%FAILED_COUNT%"=="" SET FAILED_COUNT=An unknown number of
echo %FAILED_COUNT% failed transfer(s).
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
echo Usage: 01.logs_transfers_GET.bat [ACCOUNT]
EXIT /B 2
