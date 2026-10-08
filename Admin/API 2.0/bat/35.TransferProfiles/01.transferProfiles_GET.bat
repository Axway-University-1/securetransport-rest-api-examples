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
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
SET PATTERN=%~2
IF "%PATTERN%"=="" SET PATTERN=*
SET ACCOUNT_ARGS=
IF NOT "%ACCOUNT%"=="" SET ACCOUNT_ARGS=--data-urlencode "account=%ACCOUNT%"
SET RESPONSE_FILE=%TEMP%\tprof_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Transfer profiles on the server: %%N

echo.
echo The profiles matching %PATTERN%: id, account/name, default, mappings, file label, mode:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %ACCOUNT_ARGS% --data-urlencode "name=%PATTERN%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.default) { 'default' } else { '-' }; '  {0}  {1}/{2}  {3}  send {4}  receive {5}  {6}  {7}' -f $p.id, $p.account, $p.name, $d, $p.sendMapping, $p.receiveMapping, $p.fileLabelOption, $p.transferMode }"

echo.
echo Only the default ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %ACCOUNT_ARGS% --data-urlencode "name=%PATTERN%" ^
  --data-urlencode "default=true" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.default) { 'default' } else { '-' }; '  {0}  {1}/{2}  {3}  send {4}  receive {5}  {6}  {7}' -f $p.id, $p.account, $p.name, $d, $p.sendMapping, $p.receiveMapping, $p.fileLabelOption, $p.transferMode }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
