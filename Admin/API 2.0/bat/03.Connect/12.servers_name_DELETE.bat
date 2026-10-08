@echo off
REM ==============================================================================
REM Script Name: 12.servers_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a server using the `/servers/{name}` endpoint.
REM It demonstrates:
REM - A conditional DELETE request after checking server existence (HEAD)
REM - Printing the HTTP code of each delete, and stopping with exit 1 when the server refuses one
REM
REM Usage:
REM 12.servers_name_DELETE.bat [NAME...]
REM
REM   NAME  the servers to delete, by name (default: SSH_TEST_SERVER_1 and SSH_TEST_SERVER_2, the two 07.servers_POST.bat creates)
REM
REM Risk: config - removes a protocol server
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The server name must be valid and exist in the system: a server that is not there is reported and skipped (the exit code
REM   stays 0), and the others are still tried. A server the server refuses to delete (a 4xx or 5xx) makes the exit code 1.
REM - A name you give is deleted if it exists, whatever its protocol: name a real server and it is gone. Run with no argument
REM   to delete only the two test servers.
REM - PowerShell is used to encode the names for the URL and show the server's own message, in place of jq.
REM - Confirmed directly: a delete is 204 with no body. A server that does not exist is answered 400 by DELETE ("Server with name X does not
REM   exist."), PATCH (the same) and PUT ("Could not update server with name X."), and **HEAD answers 400 too (no body), not the 404 that GET gives (an HTML page)**, so this
REM   script treats a HEAD that is not 200 as "does not exist" only for 400 and 404, and as an error for any other code.
REM - Exit codes: 0 when every server was deleted or was not there, 1 when a delete (or the check before it) is refused, 2 when
REM   an argument is empty (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers
SET "USAGE=Usage: 12.servers_name_DELETE.bat [NAME...]"

IF "%~1"=="" (
    SET ARGS="SSH_TEST_SERVER_1" "SSH_TEST_SERVER_2"
) ELSE (
    SET ARGS=%*
)
FOR %%N IN (%ARGS%) DO IF "%%~N"=="" (
    echo A server name must not be empty. Nothing was sent.
    echo %USAGE%
    EXIT /B 2
)

SET RESPONSE_FILE=%TEMP%\server_response_%RANDOM%.json
SET FAILED=0

FOR %%N IN (%ARGS%) DO CALL :delete_one "%%~N"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Checks that the server named in %1 exists (HEAD), and deletes it
REM ------------------------------------------------------------------------------
:delete_one
SET "NAME=%~1"
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="400" GOTO not_there
IF "%HTTP_CODE%"=="404" GOTO not_there
IF NOT "%HTTP_CODE%"=="200" GOTO cannot_check

echo Server exists. Deleting server '%NAME%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%NAME_URI%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" GOTO refused
echo Deleted '%NAME%'.
EXIT /B 0

:not_there
echo The server '%NAME%' does not exist ^(HEAD answered %HTTP_CODE%^).
EXIT /B 0

:cannot_check
echo Could not check the server '%NAME%': HEAD answered %HTTP_CODE%. Not deleted.
SET FAILED=1
EXIT /B 0

:refused
CALL :show_error
SET FAILED=1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
