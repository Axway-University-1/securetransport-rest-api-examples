@echo off
REM ==============================================================================
REM Script Name: 05.accessPolicies_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a database access policy, using the
REM `/accessPolicies/{id}` endpoint with PUT. It demonstrates:
REM - Reading the rule, changing one field, and sending the whole rule back
REM
REM Usage:
REM 05.accessPolicies_id_PUT.bat [AUTH_METHOD]
REM
REM   AUTH_METHOD  the rule's new authentication method (default scram-sha-256):
REM                trust, reject, scram-sha-256, md5 or password
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - It changes the rule 02.accessPolicies_POST.bat adds, looked up now: an id is
REM   a position, and the ones after a deleted rule move up.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to find the rule and edit it, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies

SET DATABASE=example_db
SET USER_NAME=example_user
SET AUTH_METHOD=%~1
IF "%AUTH_METHOD%"=="" SET AUTH_METHOD=scram-sha-256
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json
SET BODY_FILE=%TEMP%\policy_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"

REM The whole rule, with the one field changed, in BODY_FILE; its id printed
SET POLICY_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = @($all | Where-Object { $_.database -eq $env:DATABASE -and $_.user -eq $env:USER_NAME }); if ($p.Count) { $r = $p[-1]; $r.authMethod = $env:AUTH_METHOD; $r | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE; $r.id } } catch { }"') DO SET POLICY_ID=%%I
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF "%POLICY_ID%"=="" (
    echo There is no rule for %USER_NAME% on %DATABASE%. Run 02.accessPolicies_POST.bat first.
    EXIT /B 1
)

echo Setting rule %POLICY_ID% to %AUTH_METHOD%...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%POLICY_ID%" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
