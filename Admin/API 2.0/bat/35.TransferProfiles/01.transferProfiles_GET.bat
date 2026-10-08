@echo off
REM ==============================================================================
REM Script Name: 01.transferProfiles_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves transfer profiles using the `/transferProfiles` endpoint.
REM It demonstrates:
REM - The number of profiles on the server
REM - The profiles of one account (or of every account), one line each
REM - Only the default ones: an account has at most one default profile
REM
REM Usage:
REM 01.transferProfiles_GET.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  list only the profiles of this account (default: every account)
REM   NAME     only the profiles with this name; takes a * wildcard (default *)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Transfer profiles are a PeSIT thing. Confirmed directly: a profile for an account that has no PeSIT transfer site
REM   is refused, 400 "Account does not contain any PeSIT transfer sites."; an account that does not exist is 404.
REM - Confirmed directly: the answer is `{resultSet, result}`; `limit=0` lists all, a negative `limit` is 400. `account=` is
REM   exact (case sensitive, no wildcard, an account that does not exist just finds nothing). `name=` ignores case and takes a
REM   `*`, so `P*` finds `p1` and `P1`. A name is unique per account but case sensitive: `p1` and `P1` can both exist.
REM   `default=` takes true or false, and any other text means false (`default=abc` lists the profiles that are not the default).
REM   `transferMode`, `recordFormat`, `recordLength`, `multiSelect`, `fileLabelOption`, `sendMapping` and `additionalAttributes.key`
REM   (or `.value`) filter too; a value that is no transfer mode finds nothing, not a 400. `fields=` keeps the keys named,
REM   an unknown one is 400 "Field nope does not exist.".
REM - A profile has an `id`, and the other examples in this folder look it up by account and name.
REM - PowerShell is used to print one line per profile, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\tprof_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
SET PATTERN=%~2
IF "%PATTERN%"=="" SET PATTERN=*
IF NOT "%~3"=="" GOTO usage
SET ACCOUNT_ARGS=
IF NOT "%ACCOUNT%"=="" SET ACCOUNT_ARGS=--data-urlencode "account=%ACCOUNT%"

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=id"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Transfer profiles on the server: %%N

echo.
echo The profiles matching %PATTERN%: id, account/name, default, mappings, file label, mode:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G %ACCOUNT_ARGS% --data-urlencode "name=%PATTERN%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.default) { 'default' } else { '-' }; '  {0}  {1}/{2}  {3}  send {4}  receive {5}  {6}  {7}' -f $p.id, $p.account, $p.name, $d, $p.sendMapping, $p.receiveMapping, $p.fileLabelOption, $p.transferMode }"

echo.
echo Only the default ones:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G %ACCOUNT_ARGS% --data-urlencode "name=%PATTERN%" --data-urlencode "default=true"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.default) { 'default' } else { '-' }; '  {0}  {1}/{2}  {3}  send {4}  receive {5}  {6}  {7}' -f $p.id, $p.account, $p.name, $d, $p.sendMapping, $p.receiveMapping, $p.fileLabelOption, $p.transferMode }"
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
echo Usage: 01.transferProfiles_GET.bat [ACCOUNT [NAME]]
EXIT /B 2
