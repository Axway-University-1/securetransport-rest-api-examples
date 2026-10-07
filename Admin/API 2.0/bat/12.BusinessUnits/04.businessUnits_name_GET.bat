@echo off
REM ==============================================================================
REM Script Name: 04.businessUnits_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a business unit, using the `/businessUnits/{name}`
REM endpoint, and counts the accounts in it, with /accounts?businessUnit=.
REM
REM Usage:
REM 04.businessUnits_name_GET.bat [NAME]
REM
REM   NAME  the business unit (default Finance, which 01.businessUnits_POST.bat
REM         creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: metadata.links.accounts and .applications are ready made
REM   searches for the accounts and applications in the unit, but the server
REM   encodes them wrongly for a name with a space (businessUnit=example%2Bbu
REM   finds nothing). This script searches by the name itself instead.
REM - Confirmed directly: a nested unit also carries
REM   metadata.links.parentBusinessUnit.
REM - PowerShell is used to URL-encode the name and read the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits
SET NAME=%~1
IF "%NAME%"=="" SET NAME=Finance
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\bu_%RANDOM%.json
SET ACCOUNTS_FILE=%TEMP%\bu_accounts_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %NAME% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$b = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0}, base folder {1}' -f $b.businessUnitHierarchy, $b.baseFolder"
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts" ^
  --data-urlencode "businessUnit=%NAME%" --data-urlencode "limit=1" --data-urlencode "fields=name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%ACCOUNTS_FILE%"
powershell -NoProfile -Command "$n = (Get-Content -Raw $env:ACCOUNTS_FILE | ConvertFrom-Json).resultSet.totalCount; if (-not $n) { $n = 0 }; '  accounts in it: ' + $n"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%ACCOUNTS_FILE%" DEL "%ACCOUNTS_FILE%"
