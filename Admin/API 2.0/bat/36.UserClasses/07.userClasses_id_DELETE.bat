@echo off
REM ==============================================================================
REM Script Name: 07.userClasses_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a user class, using the `/userClasses/{id}` endpoint.
REM A class is deleted by its id, not its name, so it looks the id up by name first.
REM
REM Usage:
REM 07.userClasses_id_DELETE.bat NAME
REM
REM   NAME  the class (required). VirtClass and RealClass are refused
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This deletes data. Check the name before running it; 02.userClasses_POST.bat creates `example_userclass`. VirtClass and RealClass
REM   are the classes the server's logins fall back to: the script refuses them (exit 2), the server would not.
REM - Confirmed directly: a success is 204. An unknown id (or a second delete) is 400 "User Class with ID X does not exist.", not 404.
REM   Nothing stops the delete of a class that is IN USE: with a template account whose `templateClass` names it (the template keeps the
REM   name, and the server never checked that a class by that name exists when the template was created: 201), or with a session open in
REM   it (the session stays open and is still listed under the class's name). The next login of an account that was in it is in the next
REM   class that fits, VirtClass for a local account. The classes after it move up one place; the lab's own two are as they were.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" GOTO :usage
IF "%NAME%"=="VirtClass" GOTO :builtin
IF "%NAME%"=="RealClass" GOTO :builtin

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

SET RESPONSE_FILE=%TEMP%\uclass_response_%RANDOM%.txt
echo Deleting the user class %NAME% ^(%CLASS_ID%^)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%CLASS_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:builtin
echo %NAME% is one of the server's own classes. Refused.
EXIT /B 2

:usage
echo Usage: 07.userClasses_id_DELETE.bat NAME
EXIT /B 2
