@echo off
REM ==============================================================================
REM Script Name: 01.accessPolicies_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the database access policies using the `/accessPolicies`
REM endpoint. They are the rules of the embedded PostgreSQL database's
REM pg_hba.conf file: which connections, to which database, as which user, from
REM which address, are allowed and how they authenticate. It demonstrates:
REM - Listing every rule, in the order the database reads them
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.accessPolicies_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - Confirmed directly: the answer is a plain JSON array, not the
REM   {"result": [...]} the API reference shows.
REM - A rule's id is its line in the file. The database uses the first rule that
REM   matches a connection, so the order matters.
REM - PowerShell is used to print one rule per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when both answers are 200, 1 otherwise.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo Every database access policy, in the order they are read:
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo The same, one line each: id, connection type, database, user, address, method:
SET "URL=%MAIN_URL%?fields=id,connectionType,database,user,address,authMethod"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $all) { $a = $p.address; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}  {3}  {4}  {5}' -f $p.id, $p.connectionType, $p.database, $p.user, $a, $p.authMethod }"
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
