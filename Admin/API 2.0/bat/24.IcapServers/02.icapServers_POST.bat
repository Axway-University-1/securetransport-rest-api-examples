@echo off
REM ==============================================================================
REM Script Name: 02.icapServers_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds an ICAP server using the `/icapServers` endpoint: its name, address
REM and which transfers it scans. It is created disabled, so that nothing is sent to it
REM until 06.icapServers_name_PATCH.bat enables it.
REM
REM Usage:
REM 02.icapServers_POST.bat [NAME [URL [TYPE]]]
REM
REM   NAME  the server's name (default example_icap)
REM   URL   icap://host:port/service (default icap://icap.example.com:1344/AVSCAN)
REM   TYPE  INCOMING, OUTGOING or BOTH: which transfers it scans (default INCOMING)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An ICAP server scans transfers only for the business units that list it in
REM   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
REM - INCOMING scans uploads, OUTGOING downloads, BOTH both. maxSize (MB, 0 or less is
REM   unlimited) and previewSize (KB) are required; this script sends 10 and 1024.
REM - The answer is 201 with the new server's address in Location, and no body. A name
REM   that exists answers 409 "already exist"; one with / ; or ' answers 400.
REM - Confirmed directly: the server does not check the URL: http://x is accepted. This
REM   script requires icap://, so a typo is caught here.
REM - Confirmed directly: with scanning on, SecureTransport asks the server OPTIONS, then
REM   sends each file as a REQMOD request, with a preview of previewSize KB first.
REM   tests/integration/lib/dummy_servers.py has a FakeIcap that can stand in for one.
REM - 03.icapServers_name_HEAD.bat to 07.icapServers_name_DELETE.bat check, read, change,
REM   switch on and remove it.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_icap
SET URL=%~2
IF "%URL%"=="" SET URL=icap://icap.example.com:1344/AVSCAN
SET TYPE=%~3
IF "%TYPE%"=="" SET TYPE=INCOMING
powershell -NoProfile -Command "if ($env:NAME.Trim() -eq '' -or $env:NAME -match '[/;'']') { exit 2 }"
IF ERRORLEVEL 2 (
    echo NAME must not be blank, or contain / ; or ': %NAME%
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:URL -notmatch '^icap://[^/]+/.+') { exit 2 }"
IF ERRORLEVEL 2 (
    echo URL is icap://host:port/service: %URL%
    EXIT /B 2
)
IF NOT "%TYPE%"=="INCOMING" IF NOT "%TYPE%"=="OUTGOING" IF NOT "%TYPE%"=="BOTH" (
    echo TYPE is INCOMING, OUTGOING or BOTH, not %TYPE%.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\icap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\icap_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\icap_headers_%RANDOM%.txt

powershell -NoProfile -Command "$b = [ordered]@{ serverEnabled = $false; basicSettings = [ordered]@{ name = $env:NAME; type = $env:TYPE; url = $env:URL; maxSize = 10; previewSize = 1024; denyOnConnectionError = $false }; advancedConnectionSettings = [ordered]@{ connectionTimeout = 10; readTimeout = 30 } }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 5))"

echo Adding the ICAP server %NAME%, %URL%, scanning %TYPE% transfers, disabled...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
