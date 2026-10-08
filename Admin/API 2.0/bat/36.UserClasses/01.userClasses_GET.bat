@echo off
REM ==============================================================================
REM Script Name: 01.userClasses_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves user classes using the `/userClasses` endpoint.
REM It demonstrates:
REM - The number of classes on the server
REM - The classes matching a name, in the order the server tries them, one line each
REM - Only the enabled ones
REM
REM Usage:
REM 01.userClasses_GET.bat [NAME [USER_TYPE]]
REM
REM   NAME       list only the classes with this name; takes a * wildcard (default *)
REM   USER_TYPE  any (default), real, virtual or * : only the classes of that type. The * is the type of a class that
REM              fits both, not a wildcard, so quote it
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A user class decides which class an account is in when it logs in. The server tries the classes in `order` and the
REM   FIRST enabled one that matches wins; a class matches when its userType, userName, group and address fit the login
REM   and its expression (when there is one) is true. The lab has two classes of its own, VirtClass (virtual) and RealClass
REM   (real), that match every login of their type: never change or delete them.
REM - Confirmed directly: the answer is `{resultSet, result}`, and the list is NOT in the order of the classes: sort by `order`
REM   yourself, as this script does. `className=` ignores case and takes a `*` (`EXAMPLE_F*` finds `example_f1`). The other filters
REM   are exact and take no wildcard: `userType=` (real, virtual or the `*` type; another text finds nothing), `userName=nobody*`
REM   finds nothing when no class has that very text, `group=`, `address=`, `expression=`, `order=`. `enabled=` takes true or false
REM   and any other text means false. `limit=0` lists all, a negative `limit` is 400 "The limit should be a positive number or 0.",
REM   `limit=abc` and a negative `offset` are 400. `fields=` keeps the keys named, an unknown one is 400 "Field nope does not exist.".
REM - A class has an `id`; the other examples in this folder look it up by name.
REM - PowerShell is used to print one line per class, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=*
SET USER_TYPE=%~2
IF "%USER_TYPE%"=="" SET USER_TYPE=any
IF NOT "%USER_TYPE%"=="any" IF NOT "%USER_TYPE%"=="real" IF NOT "%USER_TYPE%"=="virtual" IF NOT "%USER_TYPE%"=="*" (
    echo USER_TYPE is any, real, virtual or *, not %USER_TYPE%.
    EXIT /B 2
)
SET TYPE_ARGS=
IF NOT "%USER_TYPE%"=="any" SET TYPE_ARGS=--data-urlencode "userType=%USER_TYPE%"
SET RESPONSE_FILE=%TEMP%\uclass_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo User classes on the server: %%N

echo.
echo The classes matching %PATTERN%, in the order they are tried: order, name, type, user, group, address, state, expression:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %TYPE_ARGS% --data-urlencode "className=%PATTERN%" --data-urlencode "limit=0" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($c in ($r.result | Sort-Object order)) { $s = if ($c.enabled) { 'enabled' } else { 'disabled' }; $e = if ($c.expression) { $c.expression } else { '-' }; '  {0}  {1}  {2}  user {3}  group {4}  address {5}  {6}  expression {7}' -f $c.order, $c.className, $c.userType, $c.userName, $c.group, $c.address, $s, $e }"

echo.
echo Only the enabled ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %TYPE_ARGS% --data-urlencode "className=%PATTERN%" --data-urlencode "limit=0" ^
  --data-urlencode "enabled=true" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($c in ($r.result | Sort-Object order)) { $s = if ($c.enabled) { 'enabled' } else { 'disabled' }; $e = if ($c.expression) { $c.expression } else { '-' }; '  {0}  {1}  {2}  user {3}  group {4}  address {5}  {6}  expression {7}' -f $c.order, $c.className, $c.userType, $c.userName, $c.group, $c.address, $s, $e }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
