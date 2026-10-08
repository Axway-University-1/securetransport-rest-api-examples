@echo off
REM ==============================================================================
REM Script Name: 04.accessPolicies_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one database access policy, using the
REM `/accessPolicies/{id}` endpoint. It demonstrates:
REM - Reading the whole rule
REM - Reading some fields only, with fields=
REM
REM Usage:
REM 04.accessPolicies_id_GET.bat [ID]
REM
REM   ID  the rule's id, its line in pg_hba.conf (default: the rule
REM       02.accessPolicies_POST.bat adds, looked up now)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - An id is a position, and the ones after a deleted rule move up. Look a rule
REM   up just before using its id.
REM - PowerShell is used to find the rule, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies

SET DATABASE=example_db
SET USER_NAME=example_user

SET POLICY_ID=%~1
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
IF NOT "%POLICY_ID%"=="" GOTO read
SET "URL=%MAIN_URL%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = @($all | Where-Object { $_.database -eq $env:DATABASE -and $_.user -eq $env:USER_NAME }); if ($p.Count) { $p[-1].id } } catch { }"') DO SET POLICY_ID=%%I
IF "%POLICY_ID%"=="" (
    echo There is no rule for %USER_NAME% on %DATABASE%. Run 02.accessPolicies_POST.bat first.
    EXIT /B 1
)

:read
echo Rule %POLICY_ID%:
SET "URL=%MAIN_URL%/%POLICY_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"

echo.
echo.
echo Only its database, user and method:
SET "URL=%MAIN_URL%/%POLICY_ID%?fields=database,user,authMethod"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"
echo.
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
echo Usage: 04.accessPolicies_id_GET.bat [ID]
EXIT /B 2
