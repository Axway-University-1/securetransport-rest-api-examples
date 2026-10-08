@echo off
REM ==============================================================================
REM Script Name: 03.sessions_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script ends one session, using the `/sessions/{id}` endpoint: the client is disconnected at once.
REM It reads the session first and says whose it is, and it can refuse to end it when it is not the
REM user's you expect.
REM
REM Usage:
REM 03.sessions_id_DELETE.bat SESSION_ID [USER]
REM
REM   SESSION_ID  FTP:..., HTTP:... or SSH:... as 01.sessions_GET.bat lists it (required: there is no default,
REM               so that running the script bare ends nothing)
REM   USER        the user you expect it to belong to: when the session is another user's, nothing is ended (optional)
REM
REM Risk: write - ends a session: the client is disconnected, its transfer in progress is cut short
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to URL-encode the id and read the session's user and protocol, in place of jq.
REM - This disconnects a real client. Take the id from 01.sessions_GET.bat and pass the user too, so that a session
REM   that has taken the place of the one you meant (ids are not reused, but check) is not ended by mistake. Try it on
REM   a test account: log in as it over FTP and keep the connection open.
REM - Confirmed directly: answers 204, and the client is cut off at once: an idle FTP client finds the connection
REM   closed (EOF) on its next command, an upload in progress ends with a broken pipe, an SSH client exits, and an
REM   EndUser API session answers 401 on the next call. The session is gone from the list. Only that session is
REM   ended: the user's other sessions (here an FTP and an HTTP one of one account) stay.
REM - Confirmed directly: a session that is already gone is 404 "Session with id ... not found"; an id that does not
REM   have the `FTP:<hash>:<number>`, `HTTP:<hash>` or `SSH:<hash>` shape is 400 "The format of the session is incorrect"
REM   (the GET gives 404 for that). The reference's `localDaemonReturn` query parameter made no difference and is
REM   not used. Ending a session does not lock the account: the user can log in again at once.
REM - Exit codes: 0 when the session was ended, 1 when it was not found, is another user's or the server refuses,
REM   2 for a missing or wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sessions
SET SESSION_ID=%~1
SET EXPECTED_USER=%~2
IF "%SESSION_ID%"=="" GOTO usage
ECHO "%SESSION_ID%" | FIND ":" > NUL
IF ERRORLEVEL 1 GOTO usage
IF NOT "%~3"=="" GOTO usage
GOTO args_ok
:usage
echo Usage: 03.sessions_id_DELETE.bat SESSION_ID [USER]   ^(SESSION_ID is FTP:..., HTTP:... or SSH:..., from 01.sessions_GET.bat^)
EXIT /B 2
:args_ok
SET RESPONSE_FILE=%TEMP%\sessions_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:SESSION_ID)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the session ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
FOR /F "delims=" %%U IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).userName"') DO SET SESSION_USER=%%U
FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).protocol"') DO SET SESSION_PROTOCOL=%%P
IF "%EXPECTED_USER%"=="" GOTO end_it
IF "%SESSION_USER%"=="%EXPECTED_USER%" GOTO end_it
echo That is a %SESSION_PROTOCOL% session of %SESSION_USER%, not of %EXPECTED_USER%: nothing was ended.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1

:end_it
echo Ending the %SESSION_PROTOCOL% session of %SESSION_USER%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
