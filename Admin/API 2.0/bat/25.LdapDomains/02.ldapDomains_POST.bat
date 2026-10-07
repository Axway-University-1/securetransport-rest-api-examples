@echo off
REM ==============================================================================
REM Script Name: 02.ldapDomains_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds an LDAP domain using the `/ldapDomains` endpoint: a directory
REM server, the account SecureTransport binds with, and where it searches for users.
REM
REM Usage:
REM 02.ldapDomains_POST.bat [NAME [HOST [PORT]]]
REM
REM   NAME  the domain's name (default example_ldap)
REM   HOST  the directory server (default: the SecureTransport server itself)
REM   PORT  its port (default 389)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An LDAP domain only authenticates users when the server's login settings turn LDAP on
REM   (see 13.Configurations/21.configurations_loginSettings_GET.bat); this script does not.
REM - LDAP_BIND_PASSWORD, the password of the bind account, is read from the environment,
REM   so set it first:
REM     SET LDAP_BIND_PASSWORD=the bind password
REM - The bind account is cn=reader,dc=example,dc=com and the base DN is
REM   ou=People,dc=example,dc=com: change BIND_DN and BASE_DN below for a real directory.
REM - Confirmed directly: bindDn and bindDnPassword are required, though the reference
REM   marks only name. A name that exists answers 409 "Duplicate domain".
REM - Confirmed directly: the server looks the host up when the domain is saved, so a name
REM   it cannot resolve answers 400 "Invalid server host". An address always works.
REM - Confirmed directly: the defaults are not the reference's: referralsAllowed and
REM   anonymousBindsAllowed both read true.
REM - The answer is 201, with the new domain's ID, not its name, at the end of Location, and
REM   no body. 08.ldapDomains_name_operations_POST_testConnection.bat tries the connection.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_ldap
SET HOST=%~2
IF "%HOST%"=="" SET HOST=%ST_SERVER%
SET PORT=%~3
IF "%PORT%"=="" SET PORT=389
SET BIND_DN=cn=reader,dc=example,dc=com
SET BASE_DN=ou=People,dc=example,dc=com
IF "%LDAP_BIND_PASSWORD%"=="" (
    echo Set LDAP_BIND_PASSWORD to the bind account's password first.
    EXIT /B 2
)
IF "%NAME: =%"=="" (
    echo NAME and HOST must not be blank.
    EXIT /B 2
)
IF "%HOST: =%"=="" (
    echo NAME and HOST must not be blank.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:PORT -notmatch '^[0-9]+$' -or [int64]$env:PORT -gt 65535) { exit 2 }"
IF ERRORLEVEL 2 (
    echo PORT is a number up to 65535: %PORT%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\ldap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\ldap_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\ldap_headers_%RANDOM%.txt

powershell -NoProfile -Command "$b = [ordered]@{ name = $env:NAME; description = 'Created by 25.LdapDomains'; protocolVersion = 3; bindDn = $env:BIND_DN; bindDnPassword = $env:LDAP_BIND_PASSWORD; ldapServers = @([ordered]@{ host = $env:HOST; port = [int]$env:PORT }); ldapSearches = [ordered]@{ baseDn = $env:BASE_DN; searchAttribute = 'UID' } }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 5))"

echo Adding the LDAP domain %NAME%, directory at %HOST%:%PORT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%B
powershell -NoProfile -Command "'Its id: ' + $env:LOCATION.Substring($env:LOCATION.LastIndexOf([char]47) + 1)"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
