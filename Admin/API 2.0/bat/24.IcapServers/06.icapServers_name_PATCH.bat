@echo off
REM ==============================================================================
REM Script Name: 06.icapServers_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes an ICAP server using the `/icapServers/{name}` endpoint with PATCH:
REM it switches the server on or off, and what happens to a transfer when the server
REM cannot be reached.
REM
REM Usage:
REM 06.icapServers_name_PATCH.bat [NAME [ENABLED [DENY_ON_ERROR]]]
REM
REM   NAME           the server (default example_icap)
REM   ENABLED        true to scan, false to stop (default false)
REM   DENY_ON_ERROR  true to deny a transfer when the server cannot be reached, false to
REM                  let it go on (optional: left as it is)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An ICAP server scans transfers only for the business units that list it in
REM   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
REM - Confirmed directly: with the server enabled and reachable, a file it blocks is
REM   refused: the transfer ends Failed and the file is removed. With the server
REM   unreachable, DENY_ON_ERROR true refuses every file of those business units, and
REM   false lets them through. Disabled, nothing is scanned.
REM - Confirmed directly: scanning is not instant. The file is listed first, and a
REM   blocked one disappears within a few seconds.
REM - A PATCH of /basicSettings/name renames the server, as a PUT does.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_icap
SET ENABLED=%~2
IF "%ENABLED%"=="" SET ENABLED=false
SET DENY=%~3
IF NOT "%ENABLED%"=="true" IF NOT "%ENABLED%"=="false" (
    echo ENABLED is true or false, not %ENABLED%.
    EXIT /B 2
)
IF "%DENY%"=="" GOTO deny_ok
IF NOT "%DENY%"=="true" IF NOT "%DENY%"=="false" (
    echo DENY_ON_ERROR is true or false, not %DENY%.
    EXIT /B 2
)
:deny_ok
SET BODY_FILE=%TEMP%\icap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\icap_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

powershell -NoProfile -Command "$ops = @(@{ op = 'replace'; path = '/serverEnabled'; value = ($env:ENABLED -eq 'true') }); if ($env:DENY) { $ops += @{ op = 'replace'; path = '/basicSettings/denyOnConnectionError'; value = ($env:DENY -eq 'true') } }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject $ops))"

SET MESSAGE=Setting %NAME%: enabled %ENABLED%
IF NOT "%DENY%"=="" SET MESSAGE=%MESSAGE%, deny when unreachable %DENY%
echo %MESSAGE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
