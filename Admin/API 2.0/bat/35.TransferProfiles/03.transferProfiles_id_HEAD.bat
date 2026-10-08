@echo off
REM ==============================================================================
REM Script Name: 03.transferProfiles_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a transfer profile exists, using the `/transferProfiles/{id}`
REM endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the profile's id,
REM so the script looks the id up by account and name first.
REM
REM Usage:
REM 03.transferProfiles_id_HEAD.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  the account the profile belongs to (default john)
REM   NAME     the profile (default TP)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The profile is looked up by account and name, and must be the only one with that name.
REM - Confirmed directly: HEAD answers 200, or 404 with no body, also for an id that is not even well formed (`abc`).
REM   The `name=` filter ignores case and takes a * wildcard, so `p1` and `P1` (two profiles) both come back for either, and
REM   `p*` finds both: the script keeps only the exact name. The `account=` filter is exact.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=TP
SET LOOKUP_FILE=%TEMP%\tprof_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET PROFILE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET PROFILE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% transfer profiles named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%PROFILE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The transfer profile %NAME% of %ACCOUNT% exists, id %PROFILE_ID%.
) ELSE (
    echo The transfer profile %NAME% of %ACCOUNT%, id %PROFILE_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
