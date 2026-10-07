@echo off
REM ==============================================================================
REM Script Name: 38.configurations_externalStores_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a HashiCorp Vault as an external store, using the
REM `/configurations/externalStores` endpoint. The server logs in to Vault with
REM an AppRole, then reads KV version 2 secrets with the token it gets back.
REM
REM Usage:
REM 38.configurations_externalStores_POST.bat VAULT_URL [MOUNT]
REM
REM   VAULT_URL  the Vault, for example https://vault.example.com:8200
REM   MOUNT      the KV secrets engine's path (default secret)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The store is example_vault.
REM - VAULT_ROLE_ID and VAULT_SECRET_ID, the AppRole's credentials, are read from
REM   the environment, so set them first:
REM     SET VAULT_ROLE_ID=the role id
REM     SET VAULT_SECRET_ID=the secret id
REM - ${vault.api.auth.token} in the headers is replaced by the token the login
REM   answered, which the server finds at auth.token ($.auth.client_token).
REM   pathPrefix ($.data.data) is where a KV version 2 answer holds the secret.
REM - Over https the Vault's certificate must be trusted: import its CA as a
REM   trusted certificate and name it in tls.caAliases. Confirmed directly: an
REM   untrusted one fails the test with "TLS Error code 46: Certificate is
REM   unknown or untrusted!"
REM - 42.configurations_externalStores_name_operations_POST_test.bat tries it.
REM - tests/integration/lib/dummy_servers.py has a FakeVault that can stand in for
REM   a HashiCorp Vault to try these examples against.
REM - PowerShell is used to build the body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET VAULT_URL=%~1
SET MOUNT=%~2
IF "%MOUNT%"=="" SET MOUNT=secret
IF "%VAULT_URL%"=="" (
    echo Usage: 38.configurations_externalStores_POST.bat VAULT_URL [MOUNT]
    EXIT /B 2
)
IF "%VAULT_ROLE_ID%"=="" GOTO need
IF "%VAULT_SECRET_ID%"=="" GOTO need
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

powershell -NoProfile -Command "$tls = [ordered]@{ protocols=@('TLSv1.3','TLSv1.2'); skipHostNameVerification=$false }; $body = [ordered]@{ name='example_vault'; version='2'; baseUrl=$env:VAULT_URL; uri=('/v1/' + $env:MOUNT + '/data'); method='GET'; pathPrefix='$.data.data'; cacheTimeout=600; authHeader='X-Vault-Token'; headers=[ordered]@{ 'X-Vault-Token'='${vault.api.auth.token}'; 'Content-Type'='application/json' }; openTimeout=5; readTimeout=30; maxRetries=3; retryIntervalMs=100; tls=$tls; auth=[ordered]@{ baseUrl=$env:VAULT_URL; uri='/v1/auth/approle/login'; body=[ordered]@{ role_id=$env:VAULT_ROLE_ID; secret_id=$env:VAULT_SECRET_ID }; token='$.auth.client_token'; openTimeout=5; readTimeout=30; maxRetries=3; retryIntervalMs=100; headers=[ordered]@{ 'Content-Type'='application/json'; 'Accept'='application/json' }; tls=$tls } }; $body | ConvertTo-Json -Compress -Depth 10 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Adding the external store example_vault, %VAULT_URL%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/externalStores" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
GOTO :EOF

:need
echo Set VAULT_ROLE_ID and VAULT_SECRET_ID first.
EXIT /B 2
