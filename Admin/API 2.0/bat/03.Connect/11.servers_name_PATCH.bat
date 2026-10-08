@echo off
REM ==============================================================================
REM Script Name: 11.servers_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script demonstrates how to PATCH an SSH server configuration using curl.
REM It performs:
REM - A PATCH to update the port
REM - A PATCH to remove RSA keys from the publicKeys field
REM
REM Usage:
REM 11.servers_name_PATCH.bat [NAME [PORT]]
REM
REM   NAME  the SSH server to change (default SSH_TEST_SERVER_1, the one 07.servers_POST.bat creates)
REM   PORT  the new port, 1 to 65535 (default 8026)
REM
REM Risk: config - changes a protocol server
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The PATCH method allows partial updates to specific fields. The body is a JSON Patch: an ARRAY of operations,
REM   even for one. An object on its own is refused (400 "Incorrect JSON format").
REM - The server is read first, and the script stops (exit 1) when it does not exist or is not an SSH server. It prints the port
REM   and the public keys the server had, to put them back with.
REM - `publicKeys` is ONE text, the algorithms separated by commas (`ssh-rsa,x509v3-rsa2048-sha256,...`), not an array: jq splits it,
REM   drops every entry that has `rsa` in it, and joins the rest, which is sent with `replace` on `/publicKeys`. When no entry has `rsa`
REM   in it nothing is patched for the keys, and the script says so.
REM - PowerShell is used to build both patches and edit the key list, in place of jq.
REM - Confirmed directly: a PATCH is 204 with no body. `replace` of `/port` works on a server whose port is null as well as on one that
REM   has one, and so do `add` and `remove` (the field is then null); a port over 65535 is 400 "mPort must be less than or equal to
REM   65535" and text is 400 "Something went wrong while patching the entity". `publicKeys` is not checked: an empty text and a name
REM   that is no algorithm were both accepted (204). A path that does not exist is 400 `Missing field "nonsense"`; an unknown server
REM   is 400 "Server with name X does not exist.". A server created with only a name and a protocol has the keys `ssh-rsa,
REM   x509v3-rsa2048-sha256,rsa-sha2-256,rsa-sha2-512,ecdsa-sha2-nistp256,ecdsa-sha2-nistp384,ecdsa-sha2-nistp521,ssh-ed25519`.
REM - Exit codes: 0 when every PATCH was 204, 1 when the server refuses a call, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=SSH_TEST_SERVER_1"
SET "NEW_PORT=%~2"
IF "%NEW_PORT%"=="" SET "NEW_PORT=8026"
SET "USAGE=Usage: 11.servers_name_PATCH.bat [NAME [PORT]]"
IF NOT "%~3"=="" GOTO usage
powershell -NoProfile -Command "if ($env:NEW_PORT -match '^[0-9]+$' -and $env:NEW_PORT.Length -le 5 -and [int]$env:NEW_PORT -ge 1 -and [int]$env:NEW_PORT -le 65535) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo PORT is a number from 1 to 65535, not %NEW_PORT%. Nothing was sent.
    GOTO usage
)
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET SERVER_URL=%MAIN_URL%/%NAME_URI%

SET RESPONSE_FILE=%TEMP%\server_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\server_patch_%RANDOM%.json
SET KEYS_FILE=%TEMP%\server_keys_%RANDOM%.txt
SET SERVER_FILE=%TEMP%\server_object_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%KEYS_FILE%" DEL "%KEYS_FILE%"
IF EXIST "%SERVER_FILE%" DEL "%SERVER_FILE%"
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
FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:SERVER_FILE | ConvertFrom-Json).protocol"') DO SET PROTOCOL=%%P
IF "%PROTOCOL%"=="" SET PROTOCOL=unknown
IF NOT "%PROTOCOL%"=="ssh" (
    echo The server %NAME% is a %PROTOCOL% server: this script changes SSH servers only. Nothing was changed.
    EXIT /B 1
)
FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "$p = (Get-Content -Raw $env:SERVER_FILE | ConvertFrom-Json).port; if ($null -eq $p) { 'not set' } else { $p }"') DO echo The port of %NAME% is now %%P.

echo Patching the server port...
REM A JSON Patch is an ARRAY of operations: ConvertTo-Json -InputObject @(...) keeps it one, where a piped one-element array becomes a bare object, which the server refuses (400)
powershell -NoProfile -Command "$patch = @(@{ op = 'replace'; path = '/port'; value = [int]$env:NEW_PORT }); [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject $patch -Compress -Depth 5))"
CALL :patch_server
IF ERRORLEVEL 1 EXIT /B 1

echo Patching the server publicKeys...
REM The public keys are ONE text, the algorithms separated by commas: split it, drop every entry with rsa in it, join the rest. The two texts go to a file as two lines
powershell -NoProfile -Command "$old = [string](Get-Content -Raw $env:SERVER_FILE | ConvertFrom-Json).publicKeys; $new = (($old -split ',') | Where-Object { $_ -ne '' -and $_ -cnotlike '*rsa*' }) -join ','; [IO.File]::WriteAllText($env:KEYS_FILE, $old + [Environment]::NewLine + $new)"
SET OLD_PUBLIC_KEYS=
SET NEW_PUBLIC_KEYS=
FOR /F "usebackq delims=" %%K IN (`powershell -NoProfile -Command "(Get-Content $env:KEYS_FILE)[0]"`) DO SET OLD_PUBLIC_KEYS=%%K
FOR /F "usebackq delims=" %%K IN (`powershell -NoProfile -Command "(Get-Content $env:KEYS_FILE)[1]"`) DO SET NEW_PUBLIC_KEYS=%%K
echo Public keys before removing rsa: %OLD_PUBLIC_KEYS%
echo Public keys after removal: %NEW_PUBLIC_KEYS%
CALL :patch_keys
IF ERRORLEVEL 1 EXIT /B 1

echo.
echo Done
echo Retrieve the server information to check the changes...
CALL :read_server
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "Get-Content -Raw $env:SERVER_FILE | ConvertFrom-Json | Select-Object serverName, protocol, port, publicKeys | ConvertTo-Json"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Replaces /publicKeys with the text in NEW_PUBLIC_KEYS, unless it is the one the server has (the names never hold a quote)
REM ------------------------------------------------------------------------------
:patch_keys
IF "%NEW_PUBLIC_KEYS%"=="%OLD_PUBLIC_KEYS%" (
    echo There is no rsa key to remove: the publicKeys are left as they are.
    EXIT /B 0
)
powershell -NoProfile -Command "$patch = @(@{ op = 'replace'; path = '/publicKeys'; value = $env:NEW_PUBLIC_KEYS }); [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject $patch -Compress -Depth 5))"
CALL :patch_server
EXIT /B %ERRORLEVEL%

REM ------------------------------------------------------------------------------
REM Reads the server into SERVER_FILE (a copy: RESPONSE_FILE is the answer of the PATCH that follows); 1 when it cannot
REM ------------------------------------------------------------------------------
:read_server
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%SERVER_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the server %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
COPY /Y "%RESPONSE_FILE%" "%SERVER_FILE%" >nul
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Sends the JSON Patch in BODY_FILE: prints the code, and the server's message unless it is 204
REM ------------------------------------------------------------------------------
:patch_server
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%SERVER_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
