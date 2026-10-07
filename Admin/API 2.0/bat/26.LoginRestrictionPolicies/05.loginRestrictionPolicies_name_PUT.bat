@echo off
REM ==============================================================================
REM Script Name: 05.loginRestrictionPolicies_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a login restriction policy using the `/loginRestrictionPolicies/{name}`
REM endpoint with PUT: it reads the policy, changes its description, and sends the whole policy
REM back, rules and business units included.
REM
REM Usage:
REM 05.loginRestrictionPolicies_name_PUT.bat [NAME [DESCRIPTION]]
REM
REM   NAME         the policy (default example_lrp)
REM   DESCRIPTION  the new description (default "Replaced by 05.loginRestrictionPolicies_name_PUT.bat")
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the description before, to put back with.
REM - Confirmed directly: a PUT replaces everything. A body with no rules and no business units
REM   empties both; this script sends back what it read, so nothing is lost. The rules keep
REM   their ids.
REM - Confirmed directly: a PUT whose body has another name RENAMES the policy (the old name is
REM   gone). This script sets the name back to NAME, so it cannot rename.
REM - A name that does not exist answers 404. metadata is read back and dropped.
REM - PowerShell is used to URL-encode the name and edit the policy, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET "DESCRIPTION=%~2"
IF "%DESCRIPTION%"=="" SET "DESCRIPTION=Replaced by 05.loginRestrictionPolicies_name_PUT.bat"
SET BODY_FILE=%TEMP%\lrp_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET FOUND=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.name) { 'yes' } } catch { }"') DO SET FOUND=%%V
IF NOT DEFINED FOUND (
    echo There is no login restriction policy %NAME%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The description of ' + $env:NAME + ' is now: ' + $r.description; $r.PSObject.Properties.Remove('metadata'); $r.name = $env:NAME; $r.description = $env:DESCRIPTION; [IO.File]::WriteAllText($env:BODY_FILE, ($r | ConvertTo-Json -Compress -Depth 10))"

echo Setting it to: %DESCRIPTION%
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
