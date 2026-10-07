@echo off
REM ==============================================================================
REM Script Name: 06.ldapDomains_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes an LDAP domain using the `/ldapDomains/{name}` endpoint with PATCH:
REM its description, and the port of its first server.
REM
REM Usage:
REM 06.ldapDomains_name_PATCH.bat [NAME [DESCRIPTION [PORT]]]
REM
REM   NAME         the domain (default example_ldap)
REM   DESCRIPTION  the new description (default "Patched by 06.ldapDomains_name_PATCH.bat")
REM   PORT         the new port of the first server (optional: left as it is)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A list is addressed by index: /ldapServers/0/port is the first server.
REM - Confirmed directly: adding to /ldapServers/- takes order 1 and moves the others down.
REM - Confirmed directly: /isDefault can be set to true, and then cannot be set back to
REM   false (400 "You cannot set precedence on non default domain"). It is not used here.
REM - A PATCH of /name renames the domain, as a PUT does.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_ldap
SET DESCRIPTION=%~2
IF "%DESCRIPTION%"=="" SET DESCRIPTION=Patched by 06.ldapDomains_name_PATCH.bat
SET PORT=%~3
IF "%PORT%"=="" GOTO port_ok
powershell -NoProfile -Command "if ($env:PORT -notmatch '^[0-9]+$' -or [int64]$env:PORT -gt 65535) { exit 2 }"
IF ERRORLEVEL 2 (
    echo PORT is a number up to 65535: %PORT%
    EXIT /B 2
)
:port_ok
SET BODY_FILE=%TEMP%\ldap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\ldap_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

powershell -NoProfile -Command "$ops = @(@{ op = 'replace'; path = '/description'; value = $env:DESCRIPTION }); if ($env:PORT) { $ops += @{ op = 'replace'; path = '/ldapServers/0/port'; value = [int]$env:PORT } }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject $ops))"

SET PORT_TEXT=
IF NOT "%PORT%"=="" SET PORT_TEXT= and the port of the first server ^(%PORT%^)
echo Patching %NAME%: description%PORT_TEXT%...
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
