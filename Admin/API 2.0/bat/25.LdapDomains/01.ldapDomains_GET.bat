@echo off
REM ==============================================================================
REM Script Name: 01.ldapDomains_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the LDAP domains using the `/ldapDomains` endpoint: the directories
REM SecureTransport can look users up in. It demonstrates:
REM - Counting them, and listing them with their servers and base DN
REM - One domain by its name, with name=
REM - Only the ones of one protocol version, with protocolVersion=
REM
REM Usage:
REM 01.ldapDomains_GET.bat [NAME [PROTOCOL_VERSION]]
REM
REM   NAME              list the domain with exactly this name (optional)
REM   PROTOCOL_VERSION  2 or 3: only the domains of this version (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An LDAP domain only authenticates users when the server's login settings turn LDAP on
REM   (see 13.Configurations/21.configurations_loginSettings_GET.bat); this script does not.
REM - Confirmed directly: the answer is {resultSet, result}. name= is matched exactly:
REM   no * wildcard, and not without regard to case. bindDn= too.
REM - Confirmed directly: isDefault= as a filter answers an error ("The server was
REM   unable to comply with your request") for true and for false. List them all and
REM   read isDefault, as this script does.
REM - PowerShell is used to print one domain per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
SET VERSION=%~2
IF "%VERSION%"=="" GOTO version_ok
IF "%VERSION%"=="2" GOTO version_ok
IF "%VERSION%"=="3" GOTO version_ok
echo PROTOCOL_VERSION is 2 or 3, not %VERSION%.
EXIT /B 2
:version_ok
SET RESPONSE_FILE=%TEMP%\ldap_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo LDAP domains: %%N

echo.
echo All of them: name, servers, base DN, default:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%"  --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"

IF "%NAME%"=="" GOTO no_name
echo.
echo The one named %NAME%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"
:no_name
IF "%VERSION%"=="" GOTO done
echo.
echo Only the ones using LDAP version %VERSION%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "protocolVersion=%VERSION%" --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
