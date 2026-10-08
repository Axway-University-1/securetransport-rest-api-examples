@echo off
REM ==============================================================================
REM Script Name: 01.sites_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a transfer site using the `/sites` endpoint.
REM It demonstrates:
REM - An HTTP site, built with jq, attached to an account
REM - The HTTP code, and the new site's id from the Location header
REM
REM Usage:
REM 01.sites_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site is attached to an account, which must already exist. This example
REM   uses the account "john".
REM - The host below points at ST_SERVER, which is only an example. A transfer
REM   site normally points at a partner's server.
REM - The site is called HTTP. 04.sites_id_DELETE.bat removes it again, together with the two SSH sites of
REM   02.sites_POST_ssh.bat.
REM - PowerShell is used to build the request body, in place of jq.
REM - Confirmed directly: a creation is 201 with no body and the site's address in `Location`, which ends with its id; the same name on the same
REM   account again is 409 "Entry already exist.". The HTTP site is saved with no password (`password` reads back null).
REM - Exit codes: 0 when the site was created (201), 1 when the server refuses it. It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites

IF NOT "%~1"=="" (
    echo Usage: 01.sites_POST.bat
    EXIT /B 2
)

SET SITE_NAME=HTTP
SET ACCOUNT=john
SET PARTNER_USER=john
SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\site_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\site_headers_%RANDOM%.txt

REM Create TS: the body is built by PowerShell, so that a value with a quote or a backslash in it cannot break the JSON
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, ([ordered]@{ name = $env:SITE_NAME; type = 'http'; protocol = 'http'; account = $env:ACCOUNT; host = $env:ST_SERVER; port = '443'; downloadPattern = '*'; uploadFolder = '/'; userName = $env:PARTNER_USER } | ConvertTo-Json -Compress))"

echo Creating the HTTP site %SITE_NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
SET RC=0
IF NOT "%HTTP_CODE%"=="201" (
    CALL :show_error
    SET RC=1
) ELSE (
    CALL :show_location
)
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B %RC%

REM ------------------------------------------------------------------------------
REM Prints the id at the end of the Location header
REM ------------------------------------------------------------------------------
:show_location
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
