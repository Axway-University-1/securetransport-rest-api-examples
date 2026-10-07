@echo off
REM ==============================================================================
REM Script Name: 01.logs_audit_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads the audit log using the `/logs/audit` endpoint: who created, changed or
REM deleted what on the server, when, and from which address. It demonstrates:
REM - Counting the entries, and the ones of the last hours (duration=)
REM - The entries for one type of object, and one object by its exact name
REM - Only the entries of one kind of operation
REM
REM Usage:
REM 01.logs_audit_GET.bat [HOURS [OBJECT_TYPE [OBJECT_NAME [OPERATION]]]]
REM
REM   HOURS        how far back to look, in whole hours (default 24)
REM   OBJECT_TYPE  for example BusinessUnit or Account (optional)
REM   OBJECT_NAME  one object's exact name (optional)
REM   OPERATION    CREATE, UPDATE, DELETE or CREATE_OR_UPDATE (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The audit log is the server's record of changes made through the Admin UI and this API.
REM   Confirmed directly: it is newest first, the opposite of the server log.
REM - Confirmed directly: objectType= and objectName= are matched exactly, with case: BusinessUnit
REM   finds the units, businessunit and Business find none, and there is no * wildcard.
REM   userName= is a case sensitive part of the name.
REM - Confirmed directly: fromDate and endDate are RFC 2822 dates, for example Wed, 07 Oct 2026
REM   00:00:00 +0300; 2026-10-07 answers 400. duration= takes hours and needs no date.
REM - An operation that does not exist answers 400 "Unknown name value ... for enum class".
REM - PowerShell is used to print one entry per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/logs/audit
SET "HOURS=%~1"
IF "%HOURS%"=="" SET "HOURS=24"
SET "OBJECT_TYPE=%~2"
SET "OBJECT_NAME=%~3"
SET "OPERATION=%~4"
ECHO %HOURS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo HOURS must be a whole number of 1 or more: %HOURS%
    EXIT /B 2
)
IF "%OPERATION%"=="" GOTO operation_ok
IF "%OPERATION%"=="CREATE" GOTO operation_ok
IF "%OPERATION%"=="UPDATE" GOTO operation_ok
IF "%OPERATION%"=="DELETE" GOTO operation_ok
IF "%OPERATION%"=="CREATE_OR_UPDATE" GOTO operation_ok
echo OPERATION is CREATE, UPDATE, DELETE or CREATE_OR_UPDATE, not %OPERATION%.
EXIT /B 2
:operation_ok
SET RESPONSE_FILE=%TEMP%\logs_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Audit log entries: %%N

echo.
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "duration=%HOURS%" --data-urlencode "limit=1" --data-urlencode "fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo The last %HOURS% hour^(s^): %%N entries
echo The latest 5, newest first:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "duration=%HOURS%" --data-urlencode "limit=5" --data-urlencode "fields=id,dateModified,operationType,objectType,objectName,userName,remoteAddress" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; foreach ($e in $r.result) { '  {0}  {1}  {2} {3}  by {4} from {5}' -f $e.dateModified, $e.operationType, $e.objectType, (& $d $e.objectName), (& $d $e.userName), (& $d $e.remoteAddress) }"

SET FILTER=
IF NOT "%OBJECT_TYPE%"=="" SET FILTER=%FILTER% --data-urlencode "objectType=%OBJECT_TYPE%"
IF NOT "%OBJECT_NAME%"=="" SET FILTER=%FILTER% --data-urlencode "objectName=%OBJECT_NAME%"
IF NOT "%OPERATION%"=="" SET FILTER=%FILTER% --data-urlencode "operationType=%OPERATION%"
IF "%FILTER%"=="" GOTO done
echo.
echo The latest 10 entries for those filters:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %FILTER% --data-urlencode "limit=10" --data-urlencode "fields=id,dateModified,operationType,objectType,objectName,userName,remoteAddress" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; foreach ($e in $r.result) { '  {0}  {1}  {2} {3}  by {4} from {5}' -f $e.dateModified, $e.operationType, $e.objectType, (& $d $e.objectName), (& $d $e.userName), (& $d $e.remoteAddress) }"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
