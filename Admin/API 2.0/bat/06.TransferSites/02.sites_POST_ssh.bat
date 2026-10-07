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
REM 02.sites_POST_ssh.bat
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
REM - The folders are relative to the partner account's home folder, so
REM   "/outbound-drop" is <home of john>/outbound-drop.
REM - ${stenv.target} in the rename is Expression Language, filled in by
REM   SecureTransport with the file name.
REM - PowerShell is used to build the request bodies, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET PARTNER_HOST=%ST_SERVER%
SET PARTNER_SSH_PORT=8022
SET PARTNER_USER=john
IF "%PARTNER_PASSWORD%"=="" SET PARTNER_PASSWORD=change_me
SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json

REM The pull site. Every *.txt file in /outbound-drop on the partner is downloaded,
REM and arrives here with _PULLED added to its name.
powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name='SSH_PULL'; account=$env:ACCOUNT; host=$env:PARTNER_HOST; port=$env:PARTNER_SSH_PORT; userName=$env:PARTNER_USER; usePassword=$true; password=$env:PARTNER_PASSWORD; transferType='partner'; downloadFolder='/outbound-drop'; downloadPatternType='glob'; downloadPattern='*.txt'; postTransmissionActions=@{ doAsIn='${stenv.target}_PULLED' } } | ConvertTo-Json -Depth 5 -Compress" > "%BODY_FILE%"

echo Creating the SSH pull site SSH_PULL...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" -d "@%BODY_FILE%"

REM The push site. Files are uploaded to /delivered on the partner, with _PUSHED
REM added to their name.
powershell -NoProfile -Command "@{ type='ssh'; protocol='ssh'; name='SSH_PUSH'; account=$env:ACCOUNT; host=$env:PARTNER_HOST; port=$env:PARTNER_SSH_PORT; userName=$env:PARTNER_USER; usePassword=$true; password=$env:PARTNER_PASSWORD; transferType='partner'; uploadFolder='/delivered'; postTransmissionActions=@{ doAsOut='${stenv.target}_PUSHED' } } | ConvertTo-Json -Depth 5 -Compress" > "%BODY_FILE%"

echo Creating the SSH push site SSH_PUSH...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" -d "@%BODY_FILE%"

IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
