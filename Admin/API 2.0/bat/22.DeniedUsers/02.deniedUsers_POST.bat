@echo off
REM ==============================================================================
REM Script Name: 02.deniedUsers_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a login name to the denied users using the `/deniedUsers`
REM endpoint: the name can no longer log in, for good or for a number of hours.
REM
REM Usage:
REM 02.deniedUsers_POST.bat [LOGIN_NAME [HOURS [NOTE]]]
REM
REM   LOGIN_NAME  the name to block (default example_denied)
REM   HOURS       block for this many hours; leave out to block for good
REM   NOTE        why (optional)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - 03.deniedUsers_name_DELETE.bat removes the name again.
REM - The answer is 201 with the new entry's address in the Location header, and no
REM   body. A name that is already in the list answers 400 "already exists in the
REM   block list"; no loginName answers 400 "loginName must not be null".
REM - Confirmed directly: the server accepts an EMPTY loginName, and the entry
REM   then cannot be removed through the API (DELETE with an empty name answers
REM   405). This script refuses an empty name, and so should anything calling the
REM   endpoint.
REM - Confirmed directly: the server also accepts 0 and negative HOURS, which give
REM   an entry that has already expired; this script asks for 1 or more.
REM - Confirmed directly: a blocked name is refused at the EndUser login with 401
REM   "Login failed", and logs in again once it is removed. Blocking the login name
REM   of a real account stops them logging in: choose the name with care.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/deniedUsers
SET LOGIN_NAME=%~1
IF "%LOGIN_NAME%"=="" SET LOGIN_NAME=example_denied
SET HOURS=%~2
SET NOTE=%~3
IF "%LOGIN_NAME: =%"=="" (
    echo LOGIN_NAME must not be empty: the server would accept it and then not let it be removed.
    EXIT /B 2
)
IF "%HOURS%"=="" GOTO hours_ok
ECHO %HOURS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo HOURS must be a whole number of 1 or more: %HOURS%
    EXIT /B 2
)
:hours_ok
SET BODY_FILE=%TEMP%\denied_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\denied_response_%RANDOM%.txt
SET HEADERS_FILE=%TEMP%\denied_headers_%RANDOM%.txt

REM ttl is left out for a permanent block
powershell -NoProfile -Command "$b = [ordered]@{ loginName = $env:LOGIN_NAME }; if ($env:HOURS) { $b.ttl = [int]$env:HOURS }; if ($env:NOTE) { $b.note = $env:NOTE }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

SET DURATION=for good
IF NOT "%HOURS%"=="" SET DURATION=for %HOURS% hours
echo Blocking %LOGIN_NAME% %DURATION%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
