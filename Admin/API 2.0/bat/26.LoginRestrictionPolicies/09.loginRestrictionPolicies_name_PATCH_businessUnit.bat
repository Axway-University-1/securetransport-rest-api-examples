@echo off
REM ==============================================================================
REM Script Name: 09.loginRestrictionPolicies_name_PATCH_businessUnit.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script assigns a login restriction policy to a business unit, or takes it away, using
REM the `/loginRestrictionPolicies/{name}` endpoint with PATCH.
REM
REM Usage:
REM 09.loginRestrictionPolicies_name_PATCH_businessUnit.bat NAME BUSINESS_UNIT [add|remove]
REM
REM   NAME           the policy
REM   BUSINESS_UNIT  the business unit
REM   add|remove     assign it, or take it away (default add)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - NOT confirmed: that a policy assigned to a business unit changes who can log in. On
REM   the lab these examples were checked against, a policy that denies every address,
REM   assigned to a business unit, did not stop an account of that unit logging in over
REM   FTP or the EndUser API. Check it on your own server before relying on it.
REM - The unit is required: assigning a policy is meant to change what that unit's accounts can do.
REM - Confirmed directly: assigning goes to /businessUnits/-; assigning a unit that is already
REM   there changes nothing; a unit that does not exist answers 400 "Cannot find business unit".
REM   Taking one away is by its position, which this script finds in the policy.
REM - Confirmed directly: businessUnits?assignedToLoginRestrictionPolicies=, the filter the
REM   server links to, filters nothing: every value lists every unit. Read the policy instead.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
SET "BUSINESS_UNIT=%~2"
SET "ACTION=%~3"
IF "%ACTION%"=="" SET "ACTION=add"
IF "%NAME%"=="" GOTO usage
IF "%BUSINESS_UNIT%"=="" GOTO usage
IF "%ACTION%"=="add" GOTO args_ok
IF "%ACTION%"=="remove" GOTO args_ok
:usage
echo Usage: 09.loginRestrictionPolicies_name_PATCH_businessUnit.bat NAME BUSINESS_UNIT [add^|remove]
EXIT /B 2
:args_ok
SET BODY_FILE=%TEMP%\lrp_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

IF "%ACTION%"=="add" (
    powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject @(@{ op = 'add'; path = '/businessUnits/-'; value = $env:BUSINESS_UNIT })))"
    GOTO send
)
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET INDEX=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $i = 0; foreach ($u in $r.businessUnits) { if ($u -eq $env:BUSINESS_UNIT) { $i; break }; $i++ } } catch { }"') DO SET INDEX=%%I
IF NOT DEFINED INDEX (
    echo The policy %NAME% is not assigned to %BUSINESS_UNIT%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject @(@{ op = 'remove'; path = ('/businessUnits/' + $env:INDEX) })))"
:send

echo %ACTION% the business unit %BUSINESS_UNIT%, policy %NAME%...
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
