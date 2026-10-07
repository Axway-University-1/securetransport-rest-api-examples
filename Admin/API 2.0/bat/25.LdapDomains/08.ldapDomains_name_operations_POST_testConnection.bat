@echo off
REM ==============================================================================
REM Script Name: 08.ldapDomains_name_operations_POST_testConnection.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests the connection to one server of an LDAP domain using the
REM `/ldapDomains/{name}/operations` endpoint with operation=testConnection.
REM
REM Usage:
REM 08.ldapDomains_name_operations_POST_testConnection.bat [NAME [SERVER_NUMBER]]
REM
REM   NAME           the domain (default example_ldap)
REM   SERVER_NUMBER  which of its servers, counting from 1 (default 1)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The server is named by its id, which the script looks up in the domain.
REM - Confirmed directly: the answer is 200 whether or not it worked; the message says
REM   "Successful Connection." or "Connection failed." This script exits 1 for a failure.
REM - Confirmed directly: it only opens a connection to the host and port, and sends
REM   nothing: it does not bind or search. A directory that accepts connections but would
REM   refuse the bind account still reads as successful.
REM - tests/integration/lib/dummy_servers.py has a TcpSink that can be the "directory".
REM - PowerShell is used to look the server up and print the message, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/ldapDomains
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_ldap
SET NUMBER=%~2
IF "%NUMBER%"=="" SET NUMBER=1
ECHO %NUMBER%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo SERVER_NUMBER is 1 or more: %NUMBER%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\ldap_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\ldap_response_%RANDOM%.json
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET SERVER_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $s = @($r.ldapServers)[[int]$env:NUMBER - 1]; if ($s) { $s.id } } catch { }"') DO SET SERVER_ID=%%I
IF NOT DEFINED SERVER_ID (
    echo The LDAP domain %NAME% has no server number %NUMBER%.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:BODY_FILE, (@{ id = $env:SERVER_ID } | ConvertTo-Json -Compress))"

echo Testing the connection to server %NUMBER% of %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/%ENCODED%/operations?operation=testConnection" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.message; if ($r.message -like 'Successful*') { exit 0 } else { exit 1 }"
SET RESULT=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RESULT%
