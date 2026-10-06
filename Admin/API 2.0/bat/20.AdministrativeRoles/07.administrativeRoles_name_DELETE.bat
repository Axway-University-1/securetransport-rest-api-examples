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
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It deletes example_role, which 02.administrativeRoles_POST.bat creates. Only
REM   ever point it at a role you created.
REM - Confirmed directly: with targetRoleName, the role's administrators hold the
REM   target role afterwards, and the delete answers 204.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role
SET TARGET_ROLE=%~1

SET QUERY=
IF NOT "%TARGET_ROLE%"=="" (
    SET QUERY=-G --data-urlencode "targetRoleName=%TARGET_ROLE%"
    echo Deleting the role %ROLE%, moving its administrators to %TARGET_ROLE%...
) ELSE (
    echo Deleting the role %ROLE%...
)
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ROLE%" %QUERY% -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
