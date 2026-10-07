@echo off
REM ==============================================================================
REM Script Name: 03.accessPolicies_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a database access policy exists, using the
REM `/accessPolicies/{id}` endpoint with HEAD: 200 when it does, 404 when it does
REM not.
REM
REM Usage:
REM 03.accessPolicies_id_HEAD.bat [ID]
REM
REM   ID  the rule's id, its line in pg_hba.conf (default: the rule
REM       02.accessPolicies_POST.bat adds, looked up now)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - An id is a position, and the ones after a deleted rule move up. Look a rule
REM   up just before using its id; an id kept from earlier may name another rule.
REM - PowerShell is used to find the rule, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies

SET DATABASE=example_db
SET USER_NAME=example_user
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json

SET POLICY_ID=%~1
IF NOT "%POLICY_ID%"=="" GOTO :check
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = @($all | Where-Object { $_.database -eq $env:DATABASE -and $_.user -eq $env:USER_NAME }); if ($p.Count) { $p[-1].id } } catch { }"') DO SET POLICY_ID=%%I
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF "%POLICY_ID%"=="" (
    echo There is no rule for %USER_NAME% on %DATABASE%. Run 02.accessPolicies_POST.bat first.
    EXIT /B 1
)

:check
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%POLICY_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo Rule %POLICY_ID% exists.
) ELSE (
    echo Rule %POLICY_ID% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
