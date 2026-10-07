@echo off
REM ==============================================================================
REM Script Name: 07.loginRestrictionPolicies_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a login restriction policy using the `/loginRestrictionPolicies/{name}`
REM endpoint.
REM
REM Usage:
REM 07.loginRestrictionPolicies_name_DELETE.bat [NAME]
REM
REM   NAME  the policy (default example_lrp)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only delete a policy you added: the business units it was assigned to lose its rules.
REM - A name that does not exist answers 404.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
SET BODY_FILE=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

echo Deleting the login restriction policy %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
