@echo off
REM ==============================================================================
REM Script Name: 10.sites_operations_POST_test_new.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests a connection before the site is saved, using the
REM `/sites/operations` endpoint with operation=testConnection: the body carries the
REM partner's address and the login, and no site is created.
REM
REM Usage:
REM 10.sites_operations_POST_test_new.bat [ACCOUNT [PROTOCOL [HOST [PORT [USER [SECURE]]]]]]
REM
REM   ACCOUNT   the account the site would belong to (default john, or ST_EXAMPLE_ACCOUNT)
REM   PROTOCOL  ssh, ftp or http (default ssh)
REM   HOST      the partner's host (default ST_SERVER)
REM   PORT      the partner's port (default 8022, or ST_SSH_PORT)
REM   USER      the login (default: the account)
REM   SECURE    true or false, for an FTP or HTTP partner over TLS (default false)
REM
REM   SITE_PASSWORD  the partner's password, in the environment:
REM     SET SITE_PASSWORD=the password
REM
REM Risk: read - opens a connection to the partner, changes nothing
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It exits 0 when the connection and the login both worked, 1 otherwise, 2 when an argument
REM   or SITE_PASSWORD is wrong. The partner here is SecureTransport itself: the defaults are its
REM   SSH port, logging in as the account. Point it at a real partner's server instead.
REM - Confirmed directly: for a site that is not saved the body needs an `account` that exists
REM   (400 "Cannot perform a test operation for a non saved site. Account null does not
REM   exist." without it), a `name` (any text; nothing is saved under it), `host`, `port` and
REM   `protocol`, and the login in `username` and `password` with `usePassword` "true": the
REM   field is `username` in lower case here, not `userName` as in a site. An HTTP partner on
REM   SecureTransport's own HTTPS port needs `isSecure` "true".
REM - The answer is 200 whether or not the test worked; see 09.sites_operations_POST_test.bat. A wrong
REM   password counts against the account the login is for, two failed attempts for SSH, and a
REM   second wrong test locks it (see 09.sites_operations_POST_test.bat).
REM - PowerShell is used to build the request, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET PROTOCOL=%~2
IF "%PROTOCOL%"=="" SET PROTOCOL=ssh
SET PARTNER_HOST=%~3
IF "%PARTNER_HOST%"=="" SET PARTNER_HOST=%ST_SERVER%
SET PARTNER_PORT=%~4
IF "%PARTNER_PORT%"=="" SET "PARTNER_PORT=%ST_SSH_PORT%"
IF "%PARTNER_PORT%"=="" SET "PARTNER_PORT=8022"
SET PARTNER_USER=%~5
IF "%PARTNER_USER%"=="" SET PARTNER_USER=%ACCOUNT%
SET SECURE=%~6
IF "%SECURE%"=="" SET SECURE=false
IF NOT "%PROTOCOL%"=="ssh" IF NOT "%PROTOCOL%"=="ftp" IF NOT "%PROTOCOL%"=="http" (
    echo PROTOCOL is ssh, ftp or http, not %PROTOCOL%.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:PARTNER_PORT -match '^[0-9]+$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo PORT is a number, not %PARTNER_PORT%.
    EXIT /B 2
)
IF NOT "%SECURE%"=="true" IF NOT "%SECURE%"=="false" (
    echo SECURE is true or false, not %SECURE%.
    EXIT /B 2
)
IF "%SITE_PASSWORD%"=="" (
    echo Set SITE_PASSWORD to the partner's password first.
    EXIT /B 2
)

SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\site_test_%RANDOM%.json
powershell -NoProfile -Command "$b = [ordered]@{ name = 'example_untested'; account = $env:ACCOUNT; protocol = $env:PROTOCOL; host = $env:PARTNER_HOST; port = $env:PARTNER_PORT; username = $env:PARTNER_USER; password = $env:SITE_PASSWORD; usePassword = 'true' }; if ($env:SECURE -eq 'true') { $b.isSecure = 'true' }; $b | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Testing %PROTOCOL%://%PARTNER_HOST%:%PARTNER_PORT% as %PARTNER_USER%...
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
