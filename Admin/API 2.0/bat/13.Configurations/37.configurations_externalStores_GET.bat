@echo off
REM ==============================================================================
REM Script Name: 37.configurations_externalStores_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the external stores, using the
REM `/configurations/externalStores` endpoint: the secret vaults (HashiCorp Vault,
REM Azure Key Vault, ...) the server fetches passwords and keys from at run time.
REM
REM Usage:
REM 37.configurations_externalStores_GET.bat [NAME]
REM
REM   NAME  list only the store with this exact name
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a name pattern ending in *, such as example*, answers
REM   404 "External Stores configuration is not valid" as soon as it matches a
REM   store: the pattern is matched against the server options that hold the
REM   stores, and also matches each store's companion option
REM   TM.ExternalStores.<name>.encryptedFields. Use an exact name, or none.
REM - Confirmed directly: fields= is ignored; every field comes back.
REM - PowerShell is used to print one store per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - That 404 (a pattern that matches a store) is shown with its status, and is exit 1, not an empty list.
REM - Exit codes: 0 when the answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
echo External stores: name, address, cache timeout:
SET "URL=%MAIN_URL%/externalStores"
SET CURL_OPTS=
IF NOT "%NAME%"=="" SET CURL_OPTS=-G --data-urlencode "name=%NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { '  {0}  {1}{2}  {3}s' -f $s.name, $s.baseUrl, $s.uri, $s.cacheTimeout }"
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
echo Usage: 37.configurations_externalStores_GET.bat [NAME]
EXIT /B 2
