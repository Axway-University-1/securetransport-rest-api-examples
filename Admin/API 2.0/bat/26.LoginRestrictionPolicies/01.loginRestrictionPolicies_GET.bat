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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when TYPE is not ALLOW_THEN_DENY or DENY_THEN_ALLOW, or there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\lrp_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/loginRestrictionPolicies
SET "PATTERN=%~1"
IF "%PATTERN%"=="" SET "PATTERN=*"
SET "TYPE=%~2"
IF NOT "%~3"=="" GOTO usage
IF "%TYPE%"=="" GOTO type_ok
IF "%TYPE%"=="ALLOW_THEN_DENY" GOTO type_ok
IF "%TYPE%"=="DENY_THEN_ALLOW" GOTO type_ok
echo TYPE is ALLOW_THEN_DENY or DENY_THEN_ALLOW, not %TYPE%.
EXIT /B 2
:type_ok

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Login restriction policies: %%N

echo.
echo The policies named %PATTERN%: name, type, rules, business units:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "name=%PATTERN%" --data-urlencode "fields=name,type,isDefault,rules,businessUnit"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"

IF NOT "%TYPE%"=="" CALL :by_type
IF ERRORLEVEL 1 EXIT /B 1

echo.
echo The default policy, which applies to every account that has none of its own:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "isDefault=true" --data-urlencode "fields=name,type,isDefault,rules,businessUnit"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The ones of type TYPE
REM ------------------------------------------------------------------------------
:by_type
echo.
echo Only the ones of type %TYPE%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "type=%TYPE%" --data-urlencode "fields=name,type,isDefault,rules,businessUnit"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($p in $r.result) { $d = if ($p.isDefault) { 'default  ' } else { '' }; $b = if ($p.businessUnits) { $p.businessUnits -join ', ' } else { '-' }; '  {0}  {1}  {2} rule(s)  {3}business units: {4}' -f $p.name, $p.type, ($p.rules | Measure-Object).Count, $d, $b }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 01.loginRestrictionPolicies_GET.bat [PATTERN [TYPE]]
EXIT /B 2
