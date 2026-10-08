@echo off
REM ==============================================================================
REM Script Name: 02.statisticsSummary_activeUsers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the users who have logged in, with the time of their last login, using the
REM `/statisticsSummary/activeUsers` endpoint.
REM It demonstrates:
REM - Paging through the list with limit and offset, and printing one line per user
REM - Keeping the users whose name holds some text, or the users who logged in after (or before) a time
REM
REM Usage:
REM 02.statisticsSummary_activeUsers_GET.bat [NAME [FROM [TO]]]
REM
REM   NAME  a part of the login name, case sensitive, no `*` (optional; empty for every user)
REM   FROM  only users whose last login was after this: yyyy-MM-dd, an RFC 2822 date or a timestamp in milliseconds (optional)
REM   TO    only users whose last login was before this, in the same formats (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print one line per user, in place of jq.
REM - Confirmed directly: the answer is `{resultSet, result}`, the result a list of `name`, `lastAccessTime` and
REM   `lastAdhocAccessTime`. `lastAccessTime` is TEXT for people, not a date to parse: `October 8, 2026, 8:43 AM`, to the minute, in
REM   the server's time zone, with a no-break space (U+202F) before AM or PM. `lastAdhocAccessTime` is an empty string for a
REM   user who never used ad hoc (file sharing by e-mail) access, which is every user on the lab.
REM - Confirmed directly: a user is listed from the FIRST LOGIN, over any protocol (an EndUser API login and an FTP login
REM   both did), and the time moves with each later login. A wrong password does not move it. A user who never logged in is not
REM   listed, and neither is the administrator that makes this call.
REM - Confirmed directly: **the list is not of the accounts that exist**. An account that is deleted stays in it, with its last
REM   login time, and a new account of the same name starts from that entry. There is no way to remove one.
REM - Confirmed directly: `name=` is a PART of the login name, case sensitive, and takes no `*` (`ohn` finds `john` and
REM   `john_doe`, `example_` every name that holds it, `EXAMPLE_` and `john*` find nothing). To get one user, pick the exact name
REM   out of the answer. `FROM` and `TO` take the
REM   three date formats the reference names, and anything else is 400 "Invalid date format. Format must be *EEE, dd MMM yyyy
REM   HH:mm:ss Z*, *yyyy-MM-dd* or a timestamp.". `lastAdhocAccessTime.from` and `.to` are not offered here.
REM - Confirmed directly: `limit=0` lists everything, a negative limit is 400 "The limit should be a positive number or 0.",
REM   `offset` skips that many, `fields=name` keeps the named keys (an unknown one is 400 "Field <name> does not exist.") and
REM   `totalCount` counts all the users that match, not the page. The default page, with no `limit`, held all 46 users of the lab,
REM   so this script asks for a page of 100 and goes on while the page is full.
REM - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/statisticsSummary/activeUsers
SET NAME=%~1
SET FROM=%~2
SET TO=%~3
IF NOT "%~4"=="" (
    echo Usage: 02.statisticsSummary_activeUsers_GET.bat [NAME [FROM [TO]]]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\statsum_%RANDOM%.json

SET EXTRA=
IF NOT "%NAME%"=="" SET EXTRA=%EXTRA% --data-urlencode "name=%NAME%"
IF NOT "%FROM%"=="" SET EXTRA=%EXTRA% --data-urlencode "lastAccessTime.from=%FROM%"
IF NOT "%TO%"=="" SET EXTRA=%EXTRA% --data-urlencode "lastAccessTime.to=%TO%"

SET LIMIT=100
SET OFFSET=0
SET FIRST=1
:page
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET -G "%MAIN_URL%" %EXTRA% --data-urlencode "limit=%LIMIT%" --data-urlencode "offset=%OFFSET%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF "%FIRST%"=="1" (
    powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Users who have logged in: {0}' -f $r.resultSet.totalCount; ''; 'User, last login, last ad hoc access:'"
    SET FIRST=0
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($u in @($r.result)) { if ($u) { $a = if ($u.lastAdhocAccessTime) { $u.lastAdhocAccessTime } else { '-' }; '  {0}  {1}  {2}' -f $u.name, $u.lastAccessTime, $a } }"
SET COUNT=0
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.returnCount"') DO SET COUNT=%%N
IF %COUNT% LSS %LIMIT% GOTO done
SET /A OFFSET=%OFFSET%+%LIMIT%
GOTO page
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
