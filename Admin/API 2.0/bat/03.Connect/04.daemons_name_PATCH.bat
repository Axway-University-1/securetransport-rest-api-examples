@echo off
REM ==============================================================================
REM Script Name: 04.daemons_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one setting of a daemon, using the `/daemons/{name}` endpoint with PATCH: a JSON Patch
REM document that replaces one field. Unlike PUT (03.daemons_name_PUT.bat) it sends only what changes.
REM It demonstrates:
REM - Patching `maxConnections` (a number), `preferBouncyCastleProvider` (a boolean) or `banner` (text), each typed correctly by jq
REM - The old value is read and printed first, with the command that puts it back
REM - The HTTP code, and an exit of 1 when the server refuses
REM
REM Usage:
REM 04.daemons_name_PATCH.bat NAME FIELD VALUE
REM
REM   NAME   the daemon: the API only accepts ssh (any other name is answered 400 by the server)
REM   FIELD  maxConnections, preferBouncyCastleProvider or banner
REM   VALUE  the new value: a whole number (the server accepts 1 to 100000), true or false, or any text ("" for no banner)
REM
REM Without all three arguments, or with a FIELD or VALUE that does not fit, the script prints this usage, sends NOTHING and exits 2.
REM
REM Risk: config - changes one setting of the SSH daemon; put it back afterwards (the script prints how)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This changes the configuration of the real daemon, so there is no default: the daemon, the field and the value are arguments. The script prints the old
REM   value, and the command that puts it back, before it changes anything.
REM - The reference says a changed configuration takes effect when the daemon restarts. This script does not restart it. An open connection is not dropped.
REM - PowerShell is used to read the old value and build the patch with the right type, in place of jq.
REM - Confirmed directly: a success is 204 with no body. The endpoint only ever accepts the name `ssh`: GET, PUT and PATCH on `http`, `ftp`,
REM   `pesit`, `as2`, `SSH` or any other name are 400 "Invalid value for parameter name, expected (ssh)". `maxConnections` must be 1 to 100000
REM   (400 "Property 'maxConnections' should be in the range from 1 to 100000" for -10, 0 and 100001, 400 "Cannot parse 'abc' to int." for text);
REM   `preferBouncyCastleProvider` must be a boolean (400 "Cannot parse 'yes' to boolean.").
REM   PATCH `replace` works on each of the three fields (204), also with `maxConnections` sent as the text "7"; a path that does not exist is 400 `Missing field "nope"`.
REM - Exit codes: 0 when the server answered 204, 1 when it refuses (or the daemon cannot be read), 2 when an argument is missing or wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons
SET NAME=%~1
SET FIELD=%~2
SET "VALUE=%~3"
SET USAGE=Usage: 04.daemons_name_PATCH.bat NAME FIELD VALUE, with FIELD maxConnections, preferBouncyCastleProvider or banner

IF [%3]==[] (
    echo This changes one setting of a daemon. Nothing was sent: it needs the daemon, the field and the value.
    echo %USAGE%
    EXIT /B 2
)
IF NOT [%4]==[] GOTO usage
powershell -NoProfile -Command "if ($env:NAME -match '^[A-Za-z0-9_-]+$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
SET KIND=
IF "%FIELD%"=="maxConnections" SET KIND=number
IF "%FIELD%"=="preferBouncyCastleProvider" SET KIND=boolean
IF "%FIELD%"=="banner" SET KIND=string
IF "%KIND%"=="" GOTO usage
IF "%KIND%"=="number" (
    powershell -NoProfile -Command "if ($env:VALUE -match '^-?[0-9]{1,9}$') { exit 0 } else { exit 1 }"
    IF ERRORLEVEL 1 GOTO usage
)
IF "%KIND%"=="boolean" IF NOT "%VALUE%"=="true" IF NOT "%VALUE%"=="false" GOTO usage

SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\daemon_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\daemon_body_%RANDOM%.json

echo Reading the daemon %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the daemon %NAME%: HTTP %HTTP_CODE%
    GOTO refused
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $v = $r.($env:FIELD); if ($v -is [bool]) { $v = ([string]$v).ToLower() }; 'The {0} of {1} is now ' -f $env:FIELD, $env:NAME | ForEach-Object { $_ + [char]39 + $v + [char]39 + '.' }; 'To put it back: 04.daemons_name_PATCH.bat {0} {1} ' -f $env:NAME, $env:FIELD | ForEach-Object { $_ + [char]34 + $v + [char]34 }"

powershell -NoProfile -Command "$v = switch ($env:KIND) { 'number' { [int]$env:VALUE } 'boolean' { $env:VALUE -eq 'true' } default { [string]$env:VALUE } }; $op = [ordered]@{ op = 'replace'; path = '/' + $env:FIELD; value = $v }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"

powershell -NoProfile -Command "'Setting it to ' + [char]39 + $env:VALUE + [char]39 + '...'"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" GOTO refused
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
echo Done. The daemon takes the new setting when it restarts.
EXIT /B 0
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
