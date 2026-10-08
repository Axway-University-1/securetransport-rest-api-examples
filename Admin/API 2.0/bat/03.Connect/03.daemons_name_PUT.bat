@echo off
REM ==============================================================================
REM Script Name: 03.daemons_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces the configuration of a daemon, using the `/daemons/{name}` endpoint with PUT.
REM It demonstrates:
REM - A PUT sends the whole object: all three settings of the SSH daemon are given and all three are sent
REM - The old settings are read and printed first, with the command that puts them back
REM - The HTTP code, and an exit of 1 when the server refuses
REM
REM Usage:
REM 03.daemons_name_PUT.bat NAME MAX_CONNECTIONS PREFER_BOUNCY_CASTLE BANNER
REM
REM   NAME                  the daemon: the API only accepts ssh (any other name is answered 400 by the server)
REM   MAX_CONNECTIONS       a whole number; the server accepts 1 to 100000
REM   PREFER_BOUNCY_CASTLE  true or false
REM   BANNER                the SSH welcome message; give "" for none. It is required: a PUT without it is refused
REM
REM Without all four arguments the script prints this usage, sends NOTHING and exits 2.
REM
REM Risk: config - changes the configuration of the SSH daemon; put it back afterwards (the script prints how)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This changes the configuration of the real daemon, so there is no default: every value is an argument. Put it back afterwards:
REM   the script prints the old settings, and the command that restores them, before it changes anything.
REM - A PUT replaces the whole object, so it needs all three settings. Confirmed directly: leaving out `banner`, or sending it as null, is not a 400 but a
REM   bare 403 "The server was unable to comply with your request"; an empty banner is fine. `maxConnections` as the text "12" is accepted.
REM - The reference says a changed configuration takes effect when the daemon restarts. This script does not restart it; the restart (05.daemons_operations_POST.bat)
REM   is disruptive. An already open connection is not dropped by this call.
REM - PowerShell is used to read the old settings and build the request body, in place of jq.
REM - Confirmed directly: a success is 204 with no body. The endpoint only ever accepts the name `ssh`: GET, PUT and PATCH on `http`, `ftp`,
REM   `pesit`, `as2`, `SSH` or any other name are 400 "Invalid value for parameter name, expected (ssh)". `maxConnections` must be 1 to 100000
REM   (400 "Property 'maxConnections' should be in the range from 1 to 100000" for -10, 0 and 100001, 400 "Cannot parse 'abc' to int." for text);
REM   `preferBouncyCastleProvider` must be a boolean (400 "Cannot parse 'yes' to boolean.").
REM - Exit codes: 0 when the server answered 204, 1 when it refuses (or the daemon cannot be read), 2 when an argument is missing or wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons
SET NAME=%~1
SET MAX_CONNECTIONS=%~2
SET PREFER_BOUNCY_CASTLE=%~3
SET "BANNER=%~4"
SET USAGE=Usage: 03.daemons_name_PUT.bat NAME MAX_CONNECTIONS PREFER_BOUNCY_CASTLE BANNER

IF [%4]==[] (
    echo This replaces the configuration of a daemon. Nothing was sent: it needs all four arguments.
    echo %USAGE%
    EXIT /B 2
)
IF NOT [%5]==[] GOTO usage
powershell -NoProfile -Command "if ($env:NAME -match '^[A-Za-z0-9_-]+$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
powershell -NoProfile -Command "if ($env:MAX_CONNECTIONS -match '^-?[0-9]{1,9}$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
IF NOT "%PREFER_BOUNCY_CASTLE%"=="true" IF NOT "%PREFER_BOUNCY_CASTLE%"=="false" GOTO usage

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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The daemon {0} is now: {1}' -f $env:NAME, ($r | ConvertTo-Json -Compress); 'To put it back: 03.daemons_name_PUT.bat {0} {1} {2} ' -f $env:NAME, $r.maxConnections, ([string]$r.preferBouncyCastleProvider).ToLower() | ForEach-Object { $_ + [char]34 + $r.banner + [char]34 }"

powershell -NoProfile -Command "$b = [ordered]@{ maxConnections = [int]$env:MAX_CONNECTIONS; preferBouncyCastleProvider = ($env:PREFER_BOUNCY_CASTLE -eq 'true'); banner = [string]$env:BANNER }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Replacing the configuration of %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" GOTO refused
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
echo Done. The daemon takes the new settings when it restarts.
EXIT /B 0
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
