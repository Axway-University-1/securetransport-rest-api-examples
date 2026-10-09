@echo off
REM ==============================================================================
REM Script Name: 09.sites_operations_POST_test.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests the connection of a saved transfer site, using the
REM `/sites/operations` endpoint with operation=testConnection: the server opens a
REM connection to the partner and logs in, as a transfer would, and sends nothing.
REM
REM Usage:
REM 09.sites_operations_POST_test.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  the account the site belongs to (default john, or ST_EXAMPLE_ACCOUNT)
REM   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.bat creates)
REM
REM   SITE_PASSWORD  optional, in the environment: test with this password instead of the one
REM                  saved with the site
REM
REM Risk: read - opens a connection to the partner, changes nothing
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It exits 0 when the connection and the login both worked, 1 otherwise.
REM - The body names the site by its id, with its name, host, port and protocol (the reference
REM   marks those required). Confirmed directly: the server fills in everything else, the user
REM   and the saved password included, from the site with that id, so nothing secret is sent. What
REM   the body does carry wins over what was saved: a wrong password, host or port in it fails the
REM   test. The protocol is the saved site's (a wrong one in the body is ignored), and a host or
REM   port left out of the body is the saved site's too.
REM - Confirmed directly: the answer is 200 whether or not the test worked. Read
REM   `connectionStatus` (could the server reach the partner) and `authenticationStatus` (did the
REM   login work), and `errorDetails` for why not: a closed port is "Connection refused", a host
REM   that does not resolve "Unknown site host: <host>", a wrong SSH password "Password
REM   authentication failed...", a wrong FTP password "530-Login failed...", a partner that is not
REM   an SSH server "Failed to negotiate transport component". SSH answers the cipher, the key
REM   algorithm and the host key's type; FTP and HTTP leave them null. An unknown id is a JSON 404.
REM - A partner that accepts the connection and then says nothing keeps the test waiting for
REM   longer than 30 seconds.
REM - A test with a wrong password is a real failed login, and counts against the account the site
REM   logs in as. Confirmed directly: one wrong SSH password counts as TWO failed attempts (the
REM   password, then keyboard-interactive), and with failedAuthMaximum at 3 a second wrong test
REM   LOCKS that account, which then refuses every login, even with the right password, until it
REM   is unlocked. A login that works in between resets the count. Do not test a real partner
REM   account's password twice in a row.
REM - Works for SSH, FTP and HTTP sites. A custom site (S3...) answers 200 as well, with its own
REM   message in errorDetails.
REM - PowerShell is used to read the id and build the request, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET NAME=%~2
IF "%NAME%"=="" SET NAME=SSH_PULL
SET LOOKUP_FILE=%TEMP%\site_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET SITE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SITE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% sites named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)
SET SITE_FILE=%TEMP%\site_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SITE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SITE_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the site %NAME% ^(id %SITE_ID%^).
    IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\site_test_%RANDOM%.json
powershell -NoProfile -Command "$s = Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json; $b = [ordered]@{ id = $s.id; name = $s.name; host = [string]$s.host; port = [string]$s.port; protocol = $s.protocol; account = $s.account }; if ($env:SITE_PASSWORD) { $b.password = $env:SITE_PASSWORD; $b.usePassword = 'true' }; $b | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"
IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"

echo Testing the connection of the site %NAME% of %ACCOUNT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/operations?operation=testConnection" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    type "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  connection:      ' + $r.connectionStatus; '  authentication:  ' + $r.authenticationStatus; if ($r.errorDetails) { '  error:           ' + $r.errorDetails }; if ($r.connectionStatus -eq 'success' -and $r.authenticationStatus -eq 'success') { exit 0 } else { exit 1 }"
SET RESULT=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RESULT%
