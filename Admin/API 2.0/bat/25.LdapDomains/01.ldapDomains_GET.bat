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
REM Risk: read
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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when PROTOCOL_VERSION is not 2 or 3, or there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\ldap_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
SET VERSION=%~2
IF NOT "%~3"=="" GOTO usage
IF "%VERSION%"=="" GOTO version_ok
IF "%VERSION%"=="2" GOTO version_ok
IF "%VERSION%"=="3" GOTO version_ok
echo PROTOCOL_VERSION is 2 or 3, not %VERSION%.
EXIT /B 2
:version_ok

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo LDAP domains: %%N

echo.
echo All of them: name, servers, base DN, default:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"

IF NOT "%NAME%"=="" CALL :by_name
IF ERRORLEVEL 1 EXIT /B 1
IF NOT "%VERSION%"=="" CALL :by_version
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The one named NAME
REM ------------------------------------------------------------------------------
:by_name
echo.
echo The one named %NAME%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "name=%NAME%" --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The ones using LDAP version VERSION
REM ------------------------------------------------------------------------------
:by_version
echo.
echo Only the ones using LDAP version %VERSION%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "protocolVersion=%VERSION%" --data-urlencode "fields=name,ldapServers,ldapSearches.baseDn,isDefault"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($d in $r.result) { $s = (@($d.ldapServers) | ForEach-Object { '{0}:{1}' -f $_.host, $_.port }) -join ', '; $b = if ($d.ldapSearches.baseDn) { $d.ldapSearches.baseDn } else { '-' }; $f = if ($d.isDefault) { 'default' } else { '-' }; '  {0}  {1}  {2}  {3}' -f $d.name, $s, $b, $f }"
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
echo Usage: 01.ldapDomains_GET.bat [NAME [PROTOCOL_VERSION]]
EXIT /B 2
