@echo off
REM ==============================================================================
REM Script Name: 07.servers_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates new server entries using the `/servers` endpoint.
REM It demonstrates:
REM - Creating a minimal server with name and protocol
REM - Duplicating an existing server by modifying its configuration
REM
REM Usage:
REM 07.servers_POST.bat [NAME [NEW_NAME [NEW_PORT]]]
REM
REM   NAME      the minimal SSH server to create (default SSH_TEST_SERVER_1)
REM   NEW_NAME  the duplicate of it (default SSH_TEST_SERVER_2); not the same as NAME
REM   NEW_PORT  the port of the duplicate, 1 to 65535 (default 8030)
REM
REM Risk: config - adds protocol servers, which open ports
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The serverName must be unique: a name that exists is refused (409) and the script stops there (exit 1).
REM - Supported protocols: ftp, ssh, http, as2, pesit. This script makes SSH ones.
REM - Neither server is started: a created server is inactive until 13.servers_operations_POST.bat starts it, so the port is only
REM   a setting until then. Take a port that nothing on the server listens on before you start one: the lab's own SSH server
REM   uses 8022 (the default here is not that one).
REM - 12.servers_name_DELETE.bat removes the two servers again.
REM - PowerShell is used to build the first body and edit the retrieved JSON for the second, in place of jq.
REM - Confirmed directly: a creation is 201 with no body, and a `Location` that is a search, `/servers?serverName=NAME`, not a
REM   path. A minimal server (only `serverName` and `protocol`) is inactive with `port` null and `isSftpEnabled` false, and carries
REM   the default ciphers and the public key algorithms. A duplicate name is 409 "Server with name X already exist.". A port that
REM   another server already uses is accepted (201) while the server is not running. A name with a space is fine. A body that
REM   lacks what the protocol needs is 400 (an http server with no port and no certificate alias: "Missing HTTPS port").
REM - Exit codes: 0 when both servers were created, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=SSH_TEST_SERVER_1"
SET "NEW_NAME=%~2"
IF "%NEW_NAME%"=="" SET "NEW_NAME=SSH_TEST_SERVER_2"
SET "NEW_PORT=%~3"
IF "%NEW_PORT%"=="" SET "NEW_PORT=8030"
SET "USAGE=Usage: 07.servers_POST.bat [NAME [NEW_NAME [NEW_PORT]]]"
IF NOT "%~4"=="" GOTO usage
IF "%NAME%"=="%NEW_NAME%" (
    echo NAME and NEW_NAME must differ. Nothing was sent.
    GOTO usage
)
powershell -NoProfile -Command "if ($env:NEW_PORT -match '^[0-9]+$' -and $env:NEW_PORT.Length -le 5 -and [int]$env:NEW_PORT -ge 1 -and [int]$env:NEW_PORT -le 65535) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo NEW_PORT is a number from 1 to 65535, not %NEW_PORT%. Nothing was sent.
    GOTO usage
)

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
REM The two creations; the exit code of the script is the one of this subroutine
REM ------------------------------------------------------------------------------
:main
REM Create a minimal SSH server
echo Creating the minimal SSH server %NAME%...
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ serverName = $env:NAME; protocol = 'ssh' } | ConvertTo-Json -Compress))"
CALL :post_server
IF ERRORLEVEL 1 EXIT /B 1

REM Duplicate an existing server with modifications
echo Creating a new server with the name: %NEW_NAME% and port: %NEW_PORT%...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the server %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)

REM Modify serverName and port: the object that was read, with exactly those fields changed
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $o | Add-Member -NotePropertyName serverName -NotePropertyValue $env:NEW_NAME -Force; $o | Add-Member -NotePropertyName port -NotePropertyValue ([int]$env:NEW_PORT) -Force; $o | Add-Member -NotePropertyName clientPasswordAuth -NotePropertyValue 'default' -Force; [IO.File]::WriteAllText($env:BODY_FILE, ($o | ConvertTo-Json -Compress -Depth 10))"
CALL :post_server
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Posts the body in BODY_FILE: prints the code, and the server's message unless it is 201
REM ------------------------------------------------------------------------------
:post_server
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
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
