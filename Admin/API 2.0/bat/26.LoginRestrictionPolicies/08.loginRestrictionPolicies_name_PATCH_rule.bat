@echo off
REM ==============================================================================
REM Script Name: 08.loginRestrictionPolicies_name_PATCH_rule.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script enables, disables or removes one rule of a login restriction policy using the
REM `/loginRestrictionPolicies/{name}` endpoint with PATCH.
REM
REM Usage:
REM 08.loginRestrictionPolicies_name_PATCH_rule.bat [NAME [RULE_NAME [ACTION]]]
REM
REM   NAME       the policy (default example_lrp)
REM   RULE_NAME  the rule (default "example rule")
REM   ACTION     enable, disable or remove (default disable)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A rule is addressed by its position in the rules list, which changes as rules are added
REM   (new ones go first) and removed. This script reads the policy and finds the position of
REM   the rule by its name, so it cannot hit another rule.
REM - A disabled rule stays in the policy and is not used until it is enabled again.
REM - PowerShell is used to URL-encode the name, find the rule and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "NAME=%~1"
IF "%NAME%"=="" SET "NAME=example_lrp"
SET "RULE_NAME=%~2"
IF "%RULE_NAME%"=="" SET "RULE_NAME=example rule"
SET "ACTION=%~3"
IF "%ACTION%"=="" SET "ACTION=disable"
IF NOT "%ACTION%"=="enable" IF NOT "%ACTION%"=="disable" IF NOT "%ACTION%"=="remove" (
    echo ACTION is enable, disable or remove, not %ACTION%.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\lrp_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\lrp_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET INDEX=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $i = 0; foreach ($u in $r.rules) { if ($u.name -eq $env:RULE_NAME) { $i; break }; $i++ } } catch { }"') DO SET INDEX=%%I
IF NOT DEFINED INDEX (
    echo The policy %NAME% has no rule named %RULE_NAME%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "if ($env:ACTION -eq 'remove') { $ops = @(@{ op = 'remove'; path = ('/rules/' + $env:INDEX) }) } else { $ops = @(@{ op = 'replace'; path = ('/rules/' + $env:INDEX + '/isEnabled'); value = ($env:ACTION -eq 'enable') }) }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -Compress -Depth 5 -InputObject $ops))"

powershell -NoProfile -Command "$env:ACTION + ' the rule ' + $env:RULE_NAME + ' of ' + $env:NAME + ' (position ' + $env:INDEX + ')...'"
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
