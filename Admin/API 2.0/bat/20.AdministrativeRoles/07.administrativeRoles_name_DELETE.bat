@echo off
REM ==============================================================================
REM Script Name: 07.administrativeRoles_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes an administrative role, using the
REM `/administrativeRoles/{name}` endpoint. It demonstrates:
REM - Moving the role's administrators to another role as it goes, with
REM   targetRoleName
REM
REM Usage:
REM 07.administrativeRoles_name_DELETE.bat [TARGET_ROLE]
REM
REM   TARGET_ROLE  the role the administrators that hold example_role move to.
REM                Without it, a role still held is not deleted.
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It deletes example_role, which 02.administrativeRoles_POST.bat creates. Only
REM   ever point it at a role you created.
REM - Confirmed directly: with targetRoleName, the role's administrators hold the
REM   target role afterwards, and the delete answers 204.
REM - Confirmed directly: a role that does not exist is 404 "No such administrative role.", and so is a targetRoleName that does not exist; in
REM   both cases nothing is deleted or moved.
REM - PowerShell is used to print the reason when the server refuses, in place of jq.
REM - What is deleted is printed first: the role is read, with its menus and the administrators that hold it (they are moved to TARGET_ROLE, or the
REM   server refuses), so that it can be created again with 02.administrativeRoles_POST.bat. A role that cannot be read stops the script (exit 1).
REM - Exit codes: 0 when the role was deleted (204), 1 when the server refuses, 2 when there are too many arguments (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role
SET "TARGET_ROLE=%~1"
IF NOT "%~2"=="" (
    echo Usage: 07.administrativeRoles_name_DELETE.bat [TARGET_ROLE]
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\role_response_%RANDOM%.json
SET HOLDERS_FILE=%TEMP%\role_holders_%RANDOM%.json

REM Read the role first, to say what is being deleted
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ROLE%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the role %ROLE% ^(HTTP %HTTP_CODE%^), so nothing was deleted.
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
SET HOLDERS_CODE=
FOR /F %%C IN ('curl -s -o "%HOLDERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators" --data-urlencode "roleName=%ROLE%" --data-urlencode "fields=loginName" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HOLDERS_CODE=%%C
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $m = (@($r.menus) -join ', '); if (-not $m) { $m = '-' }; if ($env:HOLDERS_CODE -eq '200') { $n = @((Get-Content -Raw $env:HOLDERS_FILE | ConvertFrom-Json).result | ForEach-Object { $_.loginName }); if ($n.Count -gt 0) { $h = $n -join ', ' } else { $h = 'nobody' } } else { $h = 'unknown, HTTP ' + $env:HOLDERS_CODE }; $t = ''; if ($env:TARGET_ROLE) { $t = ', moving its administrators to ' + $env:TARGET_ROLE }; 'Deleting the role {0} (menus: {1}; held by: {2}){3}...' -f $env:ROLE, $m, $h, $t"
IF EXIST "%HOLDERS_FILE%" DEL "%HOLDERS_FILE%"
SET QUERY=
IF NOT "%TARGET_ROLE%"=="" SET QUERY=-G --data-urlencode "targetRoleName=%TARGET_ROLE%"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ROLE%" %QUERY% -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
