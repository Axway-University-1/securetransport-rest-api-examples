@echo off
REM ==============================================================================
REM Script Name: 02.sessions_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one session using the `/sessions/{id}` endpoint: the user, the client, the
REM protocol and the command it is running now.
REM
REM Usage:
REM 02.sessions_id_GET.bat [SESSION_ID]
REM
REM   SESSION_ID  FTP:..., HTTP:... or SSH:... as 01.sessions_GET.bat lists it (default: the first session listed)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to look the first session up, URL-encode the id and print the summary, in place of jq.
REM - With no id the script lists the sessions and reads the first: on a server with no session open it says so
REM   and exits 1.
REM - Confirmed directly: the id may be sent as it is or with the colon encoded (`%3A`); the script encodes it with
REM   jq's @uri. `fields=` works (`fields=id,command`); an unknown field answers `{ }`.
REM - Confirmed directly: a session that is gone (it ended, or was killed) is 404 "Session with id ... was not found.";
REM   an id that is not `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>` is ALSO a 404, with the message "The format of
REM   the session is incorrect" (for the DELETE it is 400). The protocol must be in capitals (`ftp:...` is the format error).
REM - Exit codes: 0 when the session was read, 1 when not, 2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sessions
SET SESSION_ID=%~1
IF NOT "%~2"=="" (
    echo Usage: 02.sessions_id_GET.bat [SESSION_ID]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\sessions_%RANDOM%.json
IF NOT "%SESSION_ID%"=="" GOTO have_id
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $r = @(ConvertFrom-Json (Get-Content -Raw $env:RESPONSE_FILE)) | Where-Object { $_ }; if ($r) { $r[0].id } } catch { }"') DO SET SESSION_ID=%%I
IF "%SESSION_ID%"=="" (
    echo There are no sessions to read.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
:have_id
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:SESSION_ID)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the session ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $c = if ($r.command) { $r.command } else { '-' }; '  {0} session of {1} from {2}, on {3}' -f $r.protocol, $r.userName, $r.host, $r.serverName; '  command {0}, since {1}' -f $c, $r.sessionCreationTime"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
