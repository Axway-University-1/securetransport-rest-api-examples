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
REM - PowerShell is used to build the request body, in place of jq.
REM - Confirmed directly: a success is 201 with no body and the new rule's address in `Location`. A refusal is 400 with every reason
REM   in `validationErrors` ("Valid auth method values are: reject, trust, scram-sha-256, md5, password."), and changes nothing.
REM - Exit codes: 0 when the rule was added (201), 1 when the server refuses.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET DATABASE=example_db
SET USER_NAME=example_user
SET HEADERS_FILE=%TEMP%\policy_headers_%RANDOM%.txt
SET BODY_FILE=%TEMP%\policy_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\policy_response_%RANDOM%.json

powershell -NoProfile -Command "$b = [ordered]@{ connectionType = 'host'; database = $env:DATABASE; user = $env:USER_NAME; address = 'samehost'; authMethod = 'reject' }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Adding a rule that rejects %USER_NAME% on %DATABASE%, from the server itself...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"

echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
SET LOCATION=
FOR /F "tokens=2" %%L IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%L
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
IF DEFINED LOCATION FOR %%P IN ("%LOCATION%") DO echo The new rule is number %%~nxP.
EXIT /B 0
