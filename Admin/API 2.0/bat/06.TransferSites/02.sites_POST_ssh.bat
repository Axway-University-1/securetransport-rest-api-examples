@echo off
REM ==============================================================================
REM Script Name: 02.sites_POST_ssh.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates two SSH transfer sites using the `/sites` endpoint.
REM It demonstrates:
REM - A pull site, which downloads the files matching a pattern from a folder on
REM   the partner, and renames each file it receives (doAsIn)
REM - A push site, which uploads to a folder on the partner, and renames each file
REM   it sends (doAsOut)
REM
REM Usage:
REM SET PARTNER_PASSWORD=the partner account password
REM 02.sites_POST_ssh.bat [PORT]
REM
REM   PARTNER_PASSWORD  the password the sites log in with, from the environment (required: without it, or with the placeholder
REM                     change_me, the script prints this usage, sends nothing and exits 2)
REM   PORT              the partner's SSH port, 1 to 65535 (default 8022)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The sites are attached to the account "john", which must already exist.
REM - The partner here is SecureTransport itself: the sites log in to ST_SERVER
REM   over SSH, as john. Point PARTNER_HOST at a real partner's server instead.
REM   PARTNER_PASSWORD is read from the environment, so set it first:
REM     SET PARTNER_PASSWORD=the password
REM   There is no default password: a placeholder one would be saved on both sites and could never log in.
REM - The folders are relative to the partner account's home folder, so
REM   "/outbound-drop" is <home of john>/outbound-drop.
REM - ${stenv.target} in the rename is Expression Language, filled in by
REM   SecureTransport with the file name. It is not a shell variable.
REM - PowerShell is used to build the request bodies, in place of jq.
REM - 04.sites_id_DELETE.bat removes SSH_PULL and SSH_PUSH again.
REM - Confirmed directly: each creation is 201 with the site's address in `Location`, which ends with the site's id; a second one with the same name
REM   on the same account is 409 "Entry already exist.". The password is stored encrypted and reads back as `{AES128}...`, never as sent.
REM - Exit codes: 0 when both sites were created (201), 1 when the server refuses one (the other is still tried), 2 when PARTNER_PASSWORD is
REM   missing or the placeholder, or the port is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET "USAGE=Usage: SET PARTNER_PASSWORD=the password ^& 02.sites_POST_ssh.bat [PORT]"

SET ACCOUNT=john
SET PARTNER_HOST=%ST_SERVER%
SET PARTNER_SSH_PORT=8022
SET PARTNER_USER=john

REM The port may be given as the first argument; 8022 above is the default
IF NOT "%~1"=="" SET "PARTNER_SSH_PORT=%~1"
IF NOT "%~2"=="" GOTO usage
powershell -NoProfile -Command "if ($env:PARTNER_SSH_PORT -match '^[0-9]+$' -and $env:PARTNER_SSH_PORT.Length -le 5 -and [int]$env:PARTNER_SSH_PORT -ge 1 -and [int]$env:PARTNER_SSH_PORT -le 65535) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo PORT is a number from 1 to 65535. Nothing was sent.
    GOTO usage
)
IF "%PARTNER_PASSWORD%"=="" GOTO no_password
IF "%PARTNER_PASSWORD%"=="change_me" GOTO no_password

SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\site_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\site_headers_%RANDOM%.txt
SET FAILED=0

REM The pull site. Every *.txt file in /outbound-drop on the partner is downloaded,
REM and arrives here with _PULLED added to its name.
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type='ssh'; protocol='ssh'; name='SSH_PULL'; account=$env:ACCOUNT; host=$env:PARTNER_HOST; port=$env:PARTNER_SSH_PORT; userName=$env:PARTNER_USER; usePassword=$true; password=$env:PARTNER_PASSWORD; transferType='partner'; downloadFolder='/outbound-drop'; downloadPatternType='glob'; downloadPattern='*.txt'; postTransmissionActions=@{ doAsIn='${stenv.target}_PULLED' } } | ConvertTo-Json -Depth 5 -Compress))"
CALL :create_site "the SSH pull site SSH_PULL"

REM The push site. Files are uploaded to /delivered on the partner, with _PUSHED
REM added to their name.
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ type='ssh'; protocol='ssh'; name='SSH_PUSH'; account=$env:ACCOUNT; host=$env:PARTNER_HOST; port=$env:PARTNER_SSH_PORT; userName=$env:PARTNER_USER; usePassword=$true; password=$env:PARTNER_PASSWORD; transferType='partner'; uploadFolder='/delivered'; postTransmissionActions=@{ doAsOut='${stenv.target}_PUSHED' } } | ConvertTo-Json -Depth 5 -Compress))"
CALL :create_site "the SSH push site SSH_PUSH"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

:no_password
echo PARTNER_PASSWORD must be set in the environment to the password of the partner account, not left empty or as change_me. Nothing was sent.
:usage
echo %USAGE%
EXIT /B 2

REM ------------------------------------------------------------------------------
REM Posts the body in BODY_FILE as the site described in %1: prints the code and the new id, and sets FAILED when the server refuses it
REM ------------------------------------------------------------------------------
:create_site
echo Creating %~1...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
SET LOCATION=
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%B
IF "%LOCATION%"=="" EXIT /B 0
FOR /F "usebackq delims=" %%I IN (`powershell -NoProfile -Command "($env:LOCATION.Trim() -split '/')[-1]"`) DO echo New site ID: %%I
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
