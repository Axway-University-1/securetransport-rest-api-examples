@echo off
REM ==============================================================================
REM Script Name: 06.loginRestrictionPolicies_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a rule to a login restriction policy using the
REM `/loginRestrictionPolicies/{name}` endpoint with PATCH: allow or deny logins from an address,
REM optionally only while an Expression Language condition is true.
REM
REM Usage:
REM 06.loginRestrictionPolicies_name_PATCH.bat [NAME [RULE_NAME [TYPE [ADDRESS [CONDITION]]]]]
REM
REM   NAME       the policy (default example_lrp)
REM   RULE_NAME  the rule's name (default "example rule")
REM   TYPE       ALLOW or DENY (default DENY)
REM   ADDRESS    an IPv4 or IPv6 address, a network in CIDR notation, a host name, a domain such
REM              as *.example.com, or * for any (default client.example.com, a name reserved for examples)
REM   CONDITION  an Expression Language condition, for example ${currentSessions <= 3} (optional)
REM
REM Risk: write
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
REM - The condition holds ${...}, which is Expression Language, not a shell variable: single
REM   quote it when you call this script.
REM - Confirmed directly: rules are kept by name. Adding a rule whose name is already there
REM   REPLACES it; the policy then still has one rule of that name. Two rules may share an
REM   address.
REM - Confirmed directly: /rules/- puts the new rule first, not last. The order does not matter:
REM   rules of one type are one set.
REM - Confirmed directly: the address is checked ("Unknown format for client address"), the
REM   type is checked ("Valid type values are: ALLOW, DENY."), but the condition is not: an
REM   expression that is not valid is accepted.
REM - 08.loginRestrictionPolicies_name_PATCH_rule.bat enables, disables or removes a rule.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET "RULE_NAME=%~2"
IF "%RULE_NAME%"=="" SET "RULE_NAME=example rule"
SET "TYPE=%~3"
IF "%TYPE%"=="" SET "TYPE=DENY"
SET "ADDRESS=%~4"
IF "%ADDRESS%"=="" SET "ADDRESS=client.example.com"
SET "CONDITION=%~5"
powershell -NoProfile -Command "if ($env:RULE_NAME.Trim() -eq '' -or $env:RULE_NAME -match '[/;'']') { exit 2 }"
IF ERRORLEVEL 2 (
    echo RULE_NAME must not be blank, or contain / ; or ': %RULE_NAME%
    EXIT /B 2
)
IF NOT "%TYPE%"=="ALLOW" IF NOT "%TYPE%"=="DENY" (
    echo TYPE is ALLOW or DENY, not %TYPE%.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\lrp_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

powershell -NoProfile -Command "$v = [ordered]@{ name = $env:RULE_NAME; isEnabled = $true; type = $env:TYPE; clientAddress = $env:ADDRESS; description = 'Added by 06.loginRestrictionPolicies_name_PATCH.bat' }; if ($env:CONDITION) { $v.expression = $env:CONDITION }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject @(@{ op = 'add'; path = '/rules/-'; value = $v })))"

powershell -NoProfile -Command "$t = 'Adding the rule ' + $env:RULE_NAME + ' to ' + $env:NAME + ': ' + $env:TYPE + ' ' + $env:ADDRESS; if ($env:CONDITION) { $t += ', only if ' + $env:CONDITION }; $t + '...'"
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
