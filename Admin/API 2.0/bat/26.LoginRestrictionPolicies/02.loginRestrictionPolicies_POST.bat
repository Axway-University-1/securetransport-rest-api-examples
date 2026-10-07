@echo off
REM ==============================================================================
REM Script Name: 02.loginRestrictionPolicies_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a login restriction policy using the `/loginRestrictionPolicies`
REM endpoint: its name and type, with no rules yet and no business unit.
REM
REM Usage:
REM 02.loginRestrictionPolicies_POST.bat [NAME [TYPE [DESCRIPTION]]]
REM
REM   NAME         the policy's name (default example_lrp)
REM   TYPE         ALLOW_THEN_DENY or DENY_THEN_ALLOW (default ALLOW_THEN_DENY): which set of
REM                rules is evaluated first
REM   DESCRIPTION  optional
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A policy that is not assigned to a business unit and is not the default has no
REM   effect. Never make a policy the default (isDefault) to try it: that applies it to
REM   every account that has no policy of its own.
REM - NOT confirmed: that a policy assigned to a business unit changes who can log in. On
REM   the lab these examples were checked against, a policy that denies every address,
REM   assigned to a business unit, did not stop an account of that unit logging in over
REM   FTP or the EndUser API. Check it on your own server before relying on it.
REM - Confirmed directly: type is required, though the reference marks only name and type as
REM   an object; a body without it answers 400 "type must not be null". A name that exists
REM   answers 409; one with / ; or ' answers 400.
REM - The answer is 201 with the policy's address, which ends with its name, in Location.
REM - 06.loginRestrictionPolicies_name_PATCH.bat adds a rule, 09.loginRestrictionPolicies_name_PATCH_businessUnit.bat
REM   assigns it, 07.loginRestrictionPolicies_name_DELETE.bat removes it.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET "TYPE=%~2"
IF "%TYPE%"=="" SET "TYPE=ALLOW_THEN_DENY"
SET "DESCRIPTION=%~3"
powershell -NoProfile -Command "if ($env:NAME.Trim() -eq '' -or $env:NAME -match '[/;'']') { exit 2 }"
IF ERRORLEVEL 2 (
    echo NAME must not be blank, or contain / ; or ': %NAME%
    EXIT /B 2
)
IF NOT "%TYPE%"=="ALLOW_THEN_DENY" IF NOT "%TYPE%"=="DENY_THEN_ALLOW" (
    echo TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %TYPE%.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\lrp_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\lrp_headers_%RANDOM%.txt

powershell -NoProfile -Command "$b = [ordered]@{ name = $env:NAME; type = $env:TYPE }; if ($env:DESCRIPTION) { $b.description = $env:DESCRIPTION }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Creating the login restriction policy %NAME%, %TYPE%...
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
