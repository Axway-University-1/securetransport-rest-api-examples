@echo off
REM ==============================================================================
REM Script Name: 42.configurations_externalStores_name_operations_POST_test.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests an external store, using the
REM `/configurations/externalStores/{externalStoreName}/operations` endpoint with
REM operation=test: the server logs in and fetches one secret, and reports each
REM step.
REM
REM Usage:
REM 42.configurations_externalStores_name_operations_POST_test.bat SECRET_PATH [NAME]
REM
REM   SECRET_PATH  a secret to fetch, for example example/db
REM   NAME  the external store (default example_vault)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is 200 whatever the outcome; fetchStatus,
REM   connectionStatus and authenticationStatus say what worked, and message and
REM   solution what did not. The secret's values come back masked, ****.
REM - In a certificate or a site, ${fetch(externalStore, ...)} reads a secret at
REM   run time; see the option descriptions that mention it.
REM - tests/integration/lib/dummy_servers.py has a FakeVault that can stand in for
REM   a HashiCorp Vault to try these examples against.
REM - PowerShell is used to print the outcome, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET SECRET_PATH=%~1
SET NAME=%~2
IF "%NAME%"=="" SET NAME=example_vault
IF "%SECRET_PATH%"=="" (
    echo Usage: 42.configurations_externalStores_name_operations_POST_test.bat SECRET_PATH [NAME]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json
powershell -NoProfile -Command "@{ secretPath=$env:SECRET_PATH } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Testing %NAME% with the secret %SECRET_PATH%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/externalStores/%NAME%/operations?operation=test" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%:
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $d = { param($v) if ($v) { $v } else { '-' } }; '  connection: {0}, login: {1}, fetch: {2}' -f (& $d $r.connectionStatus), (& $d $r.authenticationStatus), (& $d $r.fetchStatus); if ($r.response.jsonData) { '  the secret holds: ' + (($r.response.jsonData.PSObject.Properties.Name | Sort-Object) -join ', ') }; if ($r.message) { '  ' + $r.message }; if ($r.fetchStatus -ne 'Success') { exit 1 }"
SET RESULT=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RESULT%
