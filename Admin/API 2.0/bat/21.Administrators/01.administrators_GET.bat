@echo off
REM ==============================================================================
REM Script Name: 01.administrators_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the administrators using the `/administrators` endpoint.
REM It demonstrates:
REM - Listing them, a page at a time
REM - Filtering: the administrators that hold a role, the locked ones
REM - Asking for some fields only, with fields=
REM
REM Usage:
REM 01.administrators_GET.bat [ROLE]
REM
REM   ROLE  the role to list the administrators of (default Master Administrator)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Many more filters exist: parent, isLimited, localAuthentication,
REM   dualAuthentication, the password and login times, and the API keys' dates
REM   and permissions. See the API reference.
REM - PowerShell is used to print one administrator per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\admins_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ROLE=%~1
IF "%ROLE%"=="" SET ROLE=Master Administrator
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo The first 5 administrators, login name and role:
SET "URL=%MAIN_URL%?limit=5&offset=0&fields=loginName,roleName"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo The ones that hold %ROLE%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "roleName=%ROLE%" --data-urlencode "fields=loginName,parent,locked"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { $p = $a.parent; if (-not $p) { $p = '-' }; $l = ''; if ($a.locked) { $l = '  LOCKED' }; '  {0}  created by {1}{2}' -f $a.loginName, $p, $l }"

echo.
echo The locked ones:
SET "URL=%MAIN_URL%?locked=true&fields=loginName"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($a in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  ' + $a.loginName }"
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
echo Usage: 01.administrators_GET.bat [ROLE]
EXIT /B 2
