@echo off
REM ==============================================================================
REM Script Name: 03.userClasses_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a user class exists, using the `/userClasses/{id}`
REM endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the class's id,
REM so the script looks the id up by name first.
REM
REM Usage:
REM 03.userClasses_id_HEAD.bat [NAME]
REM
REM   NAME  the class (default example_userclass)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The class is looked up by name, and must be the only one with that name.
REM - Confirmed directly: HEAD answers 200, or 404 with no body, also for an id that is not well formed. The path takes the id: the
REM   NAME in the path (`/userClasses/VirtClass`) is a 404. The `className=` filter ignores case and takes a * wildcard, so `example_x`
REM   and `EXAMPLE_X` (two classes) both come back for either and `example*` finds both: the script keeps only the exact name.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_userclass

SET LOOKUP_FILE=%TEMP%\uclass_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "className=%NAME%" --data-urlencode "fields=id,className" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET CLASS_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.className -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CLASS_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% user classes named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%CLASS_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The user class %NAME% exists, id %CLASS_ID%.
) ELSE (
    echo The user class %NAME%, id %CLASS_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
