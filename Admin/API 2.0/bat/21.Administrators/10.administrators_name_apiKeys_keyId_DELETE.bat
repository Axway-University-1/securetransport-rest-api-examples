@echo off
REM ==============================================================================
REM Script Name: 10.administrators_name_apiKeys_keyId_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script revokes an administrator's API keys, using the
REM `/administrators/{name}/api-keys/{keyId}` endpoint. A revoked key stops
REM working at once.
REM
REM Usage:
REM 10.administrators_name_apiKeys_keyId_DELETE.bat [KEY_ID]
REM
REM   KEY_ID  the key to revoke (default: every key of example_admin)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The administrator is example_admin, which 02.administrators_POST.bat creates.
REM - Confirmed directly: a revoke answers 204.
REM - PowerShell is used to read the key ids, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin
SET IDS_FILE=%TEMP%\apikey_ids_%RANDOM%.txt

IF NOT "%~1"=="" (
    echo %~1> "%IDS_FILE%"
) ELSE (
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ADMIN%/api-keys" -H "accept: application/json" -H "%REFERER_HEADER%" > "%IDS_FILE%.json"
    powershell -NoProfile -Command "foreach ($k in @(Get-Content -Raw ($env:IDS_FILE + '.json') | ConvertFrom-Json)) { $k.id }" > "%IDS_FILE%"
    IF EXIST "%IDS_FILE%.json" DEL "%IDS_FILE%.json"
)
FOR %%A IN ("%IDS_FILE%") DO IF %%~zA==0 (
    echo %ADMIN% has no API keys.
    DEL "%IDS_FILE%"
    EXIT /B 0
)

SET FAILED=
FOR /F %%K IN ('TYPE "%IDS_FILE%"') DO CALL :revoke %%K
IF EXIST "%IDS_FILE%" DEL "%IDS_FILE%"
IF DEFINED FAILED EXIT /B 1
GOTO :EOF

:revoke
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ADMIN%/api-keys/%1" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo Revoking the key %1 of %ADMIN%... HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" SET FAILED=1
GOTO :EOF
