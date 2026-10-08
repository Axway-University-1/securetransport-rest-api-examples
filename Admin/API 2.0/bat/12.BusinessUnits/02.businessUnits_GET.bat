@echo off
REM ==============================================================================
REM Script Name: 02.businessUnits_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the business units using the `/businessUnits` endpoint.
REM It demonstrates:
REM - Listing them, a page at a time
REM - Searching by name, with the * wildcard
REM - The units nested under another one, with parent=
REM
REM Usage:
REM 02.businessUnits_GET.bat [PATTERN [PARENT]]
REM
REM   PATTERN  a name, * matches anything (default *)
REM   PARENT   list the units nested under this one (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: baseFolder= is ignored, every value gives every unit.
REM - Confirmed directly: parent is always null in an answer, even for a nested
REM   unit; businessUnitHierarchy, parent/child, and
REM   metadata.links.parentBusinessUnit are where the nesting shows. parent= as a
REM   filter does work.
REM - PowerShell is used to print one unit per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\bus_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=*
SET PARENT=%~2
IF NOT "%~3"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo The first 5 business units:
SET "URL=%MAIN_URL%?limit=5&offset=0"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo The units named %PATTERN%: hierarchy, base folder:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "name=%PATTERN%" --data-urlencode "fields=businessUnitHierarchy,baseFolder"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($b in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($b) { '  {0}  {1}' -f $b.businessUnitHierarchy, $b.baseFolder } }"

IF NOT "%PARENT%"=="" CALL :children
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The units nested under PARENT
REM ------------------------------------------------------------------------------
:children
echo.
echo The units nested under %PARENT%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "parent=%PARENT%" --data-urlencode "fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($b in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($b) { '  ' + $b.name } }"
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
echo Usage: 02.businessUnits_GET.bat [PATTERN [PARENT]]
EXIT /B 2
