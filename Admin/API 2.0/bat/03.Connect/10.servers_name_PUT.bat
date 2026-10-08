@echo off
REM ==============================================================================
REM Script Name: 10.servers_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script updates an SSH server configuration using the PUT method via curl.
REM It demonstrates:
REM - A direct update with a new port
REM - A full update using retrieved server data with modified fields
REM
REM Usage:
REM 10.servers_name_PUT.bat [NAME [PORT]]
REM
REM   NAME  the SSH server to change (default SSH_TEST_SERVER_1, the one 07.servers_POST.bat creates)
REM   PORT  the new port, 1 to 65535 (default 8031)
REM
REM Risk: config - changes a protocol server
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The PUT method replaces the entire object, so all required fields must be included.
REM - The server is read first, and the script stops (exit 1) when it does not exist or is not an SSH server: a body
REM   that says `ssh` would otherwise be sent to a server of another protocol.
REM - It prints the port the server had, to put it back with. THE FIRST PUT IS A FRAGMENT, and a fragment resets what it leaves out: the second
REM   call reads the server again and sends the whole object back, with `clientPasswordAuth` set to `default` again; the
REM   ciphers and the other lists the fragment emptied stay empty (see Confirmed directly). Use it on a server you can
REM   create again, as this one is.
REM - PowerShell is used to edit the retrieved JSON, in place of jq.
REM - Confirmed directly: a PUT is 204 with no body. A fragment with only `serverName`, `protocol` and `port` answers 204 and resets
REM   `clientPasswordAuth`, `ciphers` and `keyExchangeAlgorithms` to empty text. A PUT of an unknown server is 400 "Could not update
REM   server with name X.". (An SSH body sent to an existing server of another protocol was not tried: the script reads the protocol first and refuses.)
REM - Exit codes: 0 when both PUTs were 204, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=SSH_TEST_SERVER_1"
SET "NEW_PORT=%~2"
IF "%NEW_PORT%"=="" SET "NEW_PORT=8031"
SET "USAGE=Usage: 10.servers_name_PUT.bat [NAME [PORT]]"
IF NOT "%~3"=="" GOTO usage
powershell -NoProfile -Command "if ($env:NEW_PORT -match '^[0-9]+$' -and $env:NEW_PORT.Length -le 5 -and [int]$env:NEW_PORT -ge 1 -and [int]$env:NEW_PORT -le 65535) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo PORT is a number from 1 to 65535, not %NEW_PORT%. Nothing was sent.
    GOTO usage
)
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET SERVER_URL=%MAIN_URL%/%NAME_URI%

SET RESPONSE_FILE=%TEMP%\server_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\server_body_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %RC%

:usage
echo %USAGE%
EXIT /B 2

REM ------------------------------------------------------------------------------
REM The work; the exit code of the script is the one of this subroutine
REM ------------------------------------------------------------------------------
:main
CALL :read_server
IF ERRORLEVEL 1 EXIT /B 1
SET PROTOCOL=
FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).protocol"') DO SET PROTOCOL=%%P
IF "%PROTOCOL%"=="" SET PROTOCOL=unknown
IF NOT "%PROTOCOL%"=="ssh" (
    echo The server %NAME% is a %PROTOCOL% server: this script changes SSH servers only. Nothing was changed.
    EXIT /B 1
)
FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "$p = (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).port; if ($null -eq $p) { 'not set' } else { $p }"') DO echo The port of %NAME% is now %%P ^(the PUT below sets %NEW_PORT%^).

REM Direct PUT update
echo Replacing the server with a body of only its name, protocol and port...
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ serverName = $env:NAME; protocol = 'ssh'; port = [int]$env:NEW_PORT } | ConvertTo-Json -Compress))"
CALL :put_server
IF ERRORLEVEL 1 EXIT /B 1

REM Retrieve and modify server configuration
CALL :read_server
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $o | Add-Member -NotePropertyName port -NotePropertyValue ([int]$env:NEW_PORT) -Force; $o | Add-Member -NotePropertyName clientPasswordAuth -NotePropertyValue 'default' -Force; [IO.File]::WriteAllText($env:BODY_FILE, ($o | ConvertTo-Json -Compress -Depth 10))"
echo Replacing the server with the whole object read back, port %NEW_PORT% and clientPasswordAuth default...
CALL :put_server
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Reads the server into RESPONSE_FILE; 1 when it cannot
REM ------------------------------------------------------------------------------
:read_server
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%SERVER_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the server %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Puts the body in BODY_FILE: prints the code, and the server's message unless it is 204
REM ------------------------------------------------------------------------------
:put_server
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%SERVER_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    EXIT /B 1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
