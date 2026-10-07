@echo off
REM ==============================================================================
REM Script Name: 43.configurations_externalStores_name_operations_POST_clearCache.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script clears a secret the server cached from an external store, using
REM the `/configurations/externalStores/{externalStoreName}/operations` endpoint
REM with operation=clearCache: the next use fetches it again, for example after
REM the secret was rotated in the vault.
REM
REM Usage:
REM 43.configurations_externalStores_name_operations_POST_clearCache.bat SECRET_PATH [NAME]
REM
REM   SECRET_PATH  the secret, for example example/db
REM   NAME  the external store (default example_vault)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is 200, "Cache was cleared successfully for
REM   external store ... and secret path ...".
REM - PowerShell is used to build the body and print the answer, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET SECRET_PATH=%~1
SET NAME=%~2
IF "%NAME%"=="" SET NAME=example_vault
IF "%SECRET_PATH%"=="" (
    echo Usage: 43.configurations_externalStores_name_operations_POST_clearCache.bat SECRET_PATH [NAME]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json
powershell -NoProfile -Command "@{ secretPath=$env:SECRET_PATH } | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/externalStores/%NAME%/operations?operation=clearCache" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
echo HTTP %HTTP_CODE%
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.message) { $r.message } else { $r } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%HTTP_CODE%"=="200" EXIT /B 1
