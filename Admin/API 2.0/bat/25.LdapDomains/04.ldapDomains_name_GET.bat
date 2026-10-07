@echo off
REM ==============================================================================
REM Script Name: 04.ldapDomains_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one LDAP domain using the `/ldapDomains/{name}` endpoint: its servers
REM with their ids, the bind account, where it searches, and the attributes it maps.
REM
REM Usage:
REM 04.ldapDomains_name_GET.bat [NAME]
REM
REM   NAME  the domain (default example_ldap)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The name goes into the path URL-encoded once, with jq's @uri.
REM - Confirmed directly: the bind password reads back encrypted, {AES128}..., never as it
REM   was sent. That text can be sent back unchanged in a PUT, which keeps the password.
REM - Each server has an id of its own: the one 08.ldapDomains_name_operations_POST_testConnection.bat
REM   needs. The domain's id, at the end of Location when it was created, is not the name.
REM - PowerShell is used to URL-encode the name and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_ldap
SET RESPONSE_FILE=%TEMP%\ldap_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %NAME% ^(HTTP %HTTP_CODE%^):
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = if ($r.isDefault) { 'the default domain' } else { 'not the default' }; '  {0}: LDAP version {1}, {2}' -f $r.name, $r.protocolVersion, $d; foreach ($s in $r.ldapServers) { '  server {0}: {1}:{2}, id {3}' -f $s.order, $s.host, $s.port, $s.id }; '  bind as {0}, search {1} by {2}' -f $r.bindDn, $r.ldapSearches.baseDn, $r.ldapSearches.searchAttribute; '  ssl {0}, tls {1}, referrals {2}, anonymous binds {3}' -f ([string]$r.sslEnabled).ToLower(), ([string]$r.tlsEnabled).ToLower(), ([string]$r.referralsAllowed).ToLower(), ([string]$r.anonymousBindsAllowed).ToLower()"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
