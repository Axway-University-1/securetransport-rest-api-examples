@echo off
REM ==============================================================================
REM Script Name: 01.loginRestrictionPolicies_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the login restriction policies using the `/loginRestrictionPolicies`
REM endpoint: the rules that say from where, and under which conditions, a user may log in.
REM It demonstrates:
REM - Counting them, and listing them with their rules and business units
REM - Searching by name, with the * wildcard
REM - Only the ones of one type, with type=
REM - The default policy, with isDefault=true
REM
REM Usage:
REM 01.loginRestrictionPolicies_GET.bat [PATTERN [TYPE]]
REM
REM   PATTERN  a policy name, * matches anything (default *)
REM   TYPE     ALLOW_THEN_DENY or DENY_THEN_ALLOW: only the policies of this type (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is {resultSet, result}. name= takes the * wildcard and
REM   is matched without regard to case, unlike most other resources.
REM - Confirmed directly: the business units are the field businessUnits, but fields= must
REM   ask for it as businessUnit (singular); fields=businessUnits answers 400. The rules are
REM   rules.
REM - PowerShell is used to print one policy per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "PATTERN=%~1"
IF "%PATTERN%"=="" SET "PATTERN=*"
SET "TYPE=%~2"
IF "%TYPE%"=="" GOTO type_ok
IF "%TYPE%"=="ALLOW_THEN_DENY" GOTO type_ok
IF "%TYPE%"=="DENY_THEN_ALLOW" GOTO type_ok
echo TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %TYPE%.
EXIT /B 2
:type_ok
SET RESPONSE_FILE=%TEMP%\lrp_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Login restriction policies: %%N

echo.
echo The policies named %PATTERN%: name, type, rules, business units:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%PATTERN%" --data-urlencode "fields=name,type,isDefault,rules,businessUnit" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"

IF "%TYPE%"=="" GOTO default_policy
echo.
echo Only the ones of type %TYPE%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "type=%TYPE%" --data-urlencode "fields=name,type,isDefault,rules,businessUnit" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"
:default_policy
echo.
echo The default policy, which applies to every account that has none of its own:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "isDefault=true" --data-urlencode "fields=name,type,isDefault,rules,businessUnit" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
