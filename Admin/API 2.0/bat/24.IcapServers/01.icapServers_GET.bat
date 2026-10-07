@echo off
REM ==============================================================================
REM Script Name: 01.icapServers_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the ICAP servers using the `/icapServers` endpoint: the antivirus
REM or data loss prevention servers SecureTransport sends transfers to, to be scanned.
REM It demonstrates:
REM - Counting them, and listing them with their type, address and whether enabled
REM - Only the enabled ones, with serverEnabled=
REM - One server by its name, with basicSettings.name=
REM - Only the ones of one type, with basicSettings.type=
REM
REM Usage:
REM 01.icapServers_GET.bat [NAME [TYPE]]
REM
REM   NAME  list the server with exactly this name (optional)
REM   TYPE  only the servers of this type: INCOMING, OUTGOING or BOTH (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An ICAP server scans transfers only for the business units that list it in
REM   enabledIcapServers (see 12.BusinessUnits), and only while it is enabled.
REM - Confirmed directly: the answer is {resultSet, result}. basicSettings.name= and
REM   basicSettings.url= are matched exactly: no * wildcard, and not without regard to
REM   case. A type that does not exist answers 400 "Unknown name value ... for enum
REM   class".
REM - PowerShell is used to print one server per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
SET TYPE=%~2
IF "%TYPE%"=="" GOTO type_ok
IF "%TYPE%"=="INCOMING" GOTO type_ok
IF "%TYPE%"=="OUTGOING" GOTO type_ok
IF "%TYPE%"=="BOTH" GOTO type_ok
echo TYPE is INCOMING, OUTGOING or BOTH, not %TYPE%.
EXIT /B 2
:type_ok
SET RESPONSE_FILE=%TEMP%\icap_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=serverEnabled" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo ICAP servers: %%N

echo.
echo All of them: name, type, address, enabled:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%"  --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"

echo.
echo Only the enabled ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "serverEnabled=true" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"

IF "%NAME%"=="" GOTO no_name
echo.
echo The one named %NAME%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "basicSettings.name=%NAME%" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"
:no_name
IF "%TYPE%"=="" GOTO done
echo.
echo Only the ones of type %TYPE%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "basicSettings.type=%TYPE%" --data-urlencode "fields=serverEnabled,basicSettings.name,basicSettings.type,basicSettings.url" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { $e = if ($s.serverEnabled) { 'enabled' } else { 'disabled' }; '  {0}  {1}  {2}  {3}' -f $s.basicSettings.name, $s.basicSettings.type, $s.basicSettings.url, $e }"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
