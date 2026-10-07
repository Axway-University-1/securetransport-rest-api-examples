@echo off
REM ==============================================================================
REM Script Name: 02.accessPolicies_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a database access policy using the `/accessPolicies`
REM endpoint: one rule of the embedded PostgreSQL database's pg_hba.conf file.
REM
REM Usage:
REM 02.accessPolicies_POST.bat
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - The rule here rejects connections to a database named example_db, as
REM   example_user, from the server itself. No such database exists, so it
REM   changes nothing. Change it carefully: a wrong rule can lock SecureTransport
REM   out of its own database.
REM - Confirmed directly: the rule is added at the end of the file, and its id -
REM   its line - comes back in the Location header. A rule that is already there
REM   can be added again.
REM - connectionType: local, host, hostssl, hostnossl, hostgssenc, hostnogssenc.
REM   authMethod: trust, reject, scram-sha-256, md5, password. address, or
REM   ipAddress and ipMask, give the client addresses.
REM - 06.accessPolicies_id_DELETE.bat removes it again.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET DATABASE=example_db
SET USER_NAME=example_user
SET HEADERS_FILE=%TEMP%\policy_headers_%RANDOM%.txt

echo Adding a rule that rejects %USER_NAME% on %DATABASE%, from the server itself...
curl -s -D "%HEADERS_FILE%" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "{\"connectionType\":\"host\",\"database\":\"%DATABASE%\",\"user\":\"%USER_NAME%\",\"address\":\"samehost\",\"authMethod\":\"reject\"}"

SET HTTP_CODE=
SET LOCATION=
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%HEADERS_FILE%"') DO SET HTTP_CODE=%%C
FOR /F "tokens=2" %%L IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%L
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"

echo HTTP %HTTP_CODE%
IF DEFINED LOCATION FOR %%P IN ("%LOCATION%") DO echo The new rule is number %%~nxP.
