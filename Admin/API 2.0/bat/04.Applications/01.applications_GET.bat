@echo off
REM ==============================================================================
REM Script Name: 01.applications_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves application data using the `/applications` endpoint.
REM It demonstrates:
REM - A full GET request for all applications
REM - A filtered GET request based on application type
REM - A GET request for application types only
REM
REM Usage:
REM 01.applications_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The type filter uses a predefined list of application types.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\applications_response_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo Get all applications...
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

SET ALL_TYPES=AccountFilePurge,AccountTTL,AdvancedRouting,ArchiveMaint,AuditLogMaint,Basic,HumanSystem,LogEntryMaint,LoginThresholdMaintenance,MBFT,PackageRetentionMaint,SentinelLinkDataMaint,SharedFolder,SiteMailbox,StandardRouter,TransferLogMaint,UnlicensedAccountMaint
FOR /F "tokens=1 delims=," %%A IN ("%ALL_TYPES%") DO SET RANDOM_TYPE=%%A

echo From all applications get one based on the type '%RANDOM_TYPE%'...
SET "URL=%MAIN_URL%?type=%RANDOM_TYPE%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo Get only the type of the available applications...
SET "URL=%MAIN_URL%?fields=type"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"
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
