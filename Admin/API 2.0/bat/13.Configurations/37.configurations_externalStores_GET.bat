@echo off
REM ==============================================================================
REM Script Name: 37.configurations_externalStores_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the external stores, using the
REM `/configurations/externalStores` endpoint: the secret vaults (HashiCorp Vault,
REM Azure Key Vault, ...) the server fetches passwords and keys from at run time.
REM
REM Usage:
REM 37.configurations_externalStores_GET.bat [NAME]
REM
REM   NAME  list only the store with this exact name
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: a name pattern ending in *, such as example*, answers
REM   404 "External Stores configuration is not valid" as soon as it matches a
REM   store: the pattern is matched against the server options that hold the
REM   stores, and also matches each store's companion option
REM   TM.ExternalStores.<name>.encryptedFields. Use an exact name, or none.
REM - Confirmed directly: fields= is ignored; every field comes back.
REM - PowerShell is used to print one store per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET NAME=%~1
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

echo External stores: name, address, cache timeout:
IF "%NAME%"=="" (
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/externalStores" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
) ELSE (
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/externalStores" --data-urlencode "name=%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($s in $r.result) { '  {0}  {1}{2}  {3}s' -f $s.name, $s.baseUrl, $s.uri, $s.cacheTimeout }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
