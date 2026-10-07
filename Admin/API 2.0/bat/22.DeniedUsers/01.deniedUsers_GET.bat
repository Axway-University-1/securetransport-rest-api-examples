@echo off
REM ==============================================================================
REM Script Name: 01.deniedUsers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the denied users using the `/deniedUsers` endpoint: the login
REM names that may not log in to SecureTransport, permanently or for a time.
REM It demonstrates:
REM - Counting them
REM - Searching by login name, with the * wildcard
REM - Only the permanent ones, and only the temporary ones (isPermanent=)
REM - Only the ones blocked since a date (blockedAt.from=)
REM
REM Usage:
REM 01.deniedUsers_GET.bat [PATTERN [SINCE]]
REM
REM   PATTERN  a login name, * matches anything (default *)
REM   SINCE    only the ones blocked on or after this date, as yyyy-MM-dd (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is {resultSet, result}; each entry has
REM   loginName, blockedAt, blockedUntil, blockedBy and note.
REM - Confirmed directly: blockedUntil null means blocked for good. A temporary
REM   entry stays in the list after it expires, until the server's blocked users
REM   cleaner removes it, so isPermanent=false can show entries that no longer
REM   block anyone.
REM - Confirmed directly: loginName= is matched without regard to case, but an
REM   entry's name is case sensitive: example_denied and EXAMPLE_DENIED can both
REM   be in the list.
REM - Confirmed directly: blockedAt and blockedUntil take .from and .to, as
REM   yyyy-MM-dd, an RFC 2822 date or a timestamp in milliseconds.
REM - PowerShell is used to print one entry per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/deniedUsers
SET PATTERN=%~1
IF "%PATTERN%"=="" SET PATTERN=*
SET SINCE=%~2
IF "%SINCE%"=="" GOTO since_ok
ECHO %SINCE%| FINDSTR /R /X "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" >NUL || (
    echo SINCE is a date as yyyy-MM-dd: %SINCE%
    EXIT /B 2
)
:since_ok
SET RESPONSE_FILE=%TEMP%\denied_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=loginName" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Denied users: %%N

echo.
echo The login names matching %PATTERN%: name, until, by, note:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "loginName=%PATTERN%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in $r.result) { $t = if ($null -eq $u.blockedUntil) { 'permanent' } else { 'until ' + $u.blockedUntil }; $b = if ($u.blockedBy) { $u.blockedBy } else { '-' }; '  {0}  {1}  by {2}  {3}' -f $u.loginName, $t, $b, $u.note }"

echo.
echo Only the permanent ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "loginName=%PATTERN%" ^
  --data-urlencode "isPermanent=true" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in $r.result) { $t = if ($null -eq $u.blockedUntil) { 'permanent' } else { 'until ' + $u.blockedUntil }; $b = if ($u.blockedBy) { $u.blockedBy } else { '-' }; '  {0}  {1}  by {2}  {3}' -f $u.loginName, $t, $b, $u.note }"

echo.
echo Only the temporary ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "loginName=%PATTERN%" ^
  --data-urlencode "isPermanent=false" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in $r.result) { $t = if ($null -eq $u.blockedUntil) { 'permanent' } else { 'until ' + $u.blockedUntil }; $b = if ($u.blockedBy) { $u.blockedBy } else { '-' }; '  {0}  {1}  by {2}  {3}' -f $u.loginName, $t, $b, $u.note }"

IF "%SINCE%"=="" GOTO done
echo.
echo Blocked on or after %SINCE%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "loginName=%PATTERN%" ^
  --data-urlencode "blockedAt.from=%SINCE%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in $r.result) { $t = if ($null -eq $u.blockedUntil) { 'permanent' } else { 'until ' + $u.blockedUntil }; $b = if ($u.blockedBy) { $u.blockedBy } else { '-' }; '  {0}  {1}  by {2}  {3}' -f $u.loginName, $t, $b, $u.note }"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
