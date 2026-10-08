@echo off
REM ==============================================================================
REM Script Name: 07.transferProfiles_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a transfer profile, using the `/transferProfiles/{id}` endpoint.
REM A profile is deleted by its id, not its name, so it looks the id up by account and name first.
REM
REM Usage:
REM 07.transferProfiles_id_DELETE.bat ACCOUNT NAME
REM
REM   ACCOUNT  the account the profile belongs to
REM   NAME     the profile (it must be the only one with that name)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This deletes data. Check the names before running it; 02.transferProfiles_POST.bat creates `example_profile`.
REM - Confirmed directly: a success is 204; a second delete, or an unknown id, is a JSON 404 "Transfer profile with id X
REM   not found or not accessible.". Deleting an account deletes its
REM   profiles.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
SET NAME=%~2
IF "%ACCOUNT%"=="" GOTO :usage
IF "%NAME%"=="" GOTO :usage
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

SET RESPONSE_FILE=%TEMP%\tprof_response_%RANDOM%.txt
echo Deleting the transfer profile %NAME% of %ACCOUNT% ^(%PROFILE_ID%^)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%PROFILE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:usage
echo Usage: 07.transferProfiles_id_DELETE.bat ACCOUNT NAME
EXIT /B 2
