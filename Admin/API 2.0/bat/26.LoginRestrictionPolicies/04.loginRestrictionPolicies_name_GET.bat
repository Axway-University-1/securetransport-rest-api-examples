@echo off
REM ==============================================================================
REM Script Name: 04.loginRestrictionPolicies_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one login restriction policy using the `/loginRestrictionPolicies/{name}`
REM endpoint: its type, its rules, and the business units it is assigned to.
REM
REM Usage:
REM 04.loginRestrictionPolicies_name_GET.bat [NAME]
REM
REM   NAME  the policy (default example_lrp)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The name goes into the path URL-encoded once, with jq's @uri.
REM - A rule has an ALLOW or DENY type, a client address (an IP address, a network in CIDR
REM   notation, a host or domain name, or * for any), an optional Expression Language
REM   condition that must also be true, and can be disabled. Rules of one type are one set;
REM   the policy's type says which set is evaluated first.
REM - Confirmed directly: the rules come back newest first, and keep their ids across a PUT: a
REM   rule is known by its name.
REM - PowerShell is used to URL-encode the name and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET RESPONSE_FILE=%TEMP%\lrp_%RANDOM%.json
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
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = if ($r.isDefault) { 'the default policy' } else { 'not the default' }; $b = if ($r.businessUnits) { $r.businessUnits -join ', ' } else { 'none' }; '  {0}: {1}, {2}' -f $r.name, $r.type, $d; '  business units: ' + $b; '  {0} rule(s): name, type, address, enabled, condition:' -f ($r.rules | Measure-Object).Count; foreach ($u in $r.rules) { $e = if ($u.isEnabled) { 'enabled' } else { 'disabled' }; $x = if ($u.expression) { $u.expression } else { '-' }; '    {0}  {1}  {2}  {3}  {4}' -f $u.name, $u.type, $u.clientAddress, $e, $x }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
