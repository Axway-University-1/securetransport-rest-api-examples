@echo off
REM ==============================================================================
REM Script Name: 05.administrativeRoles_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces an administrative role, using the
REM `/administrativeRoles/{name}` endpoint with PUT: it reads the role, sets its
REM menus, and sends the whole role back.
REM
REM Usage:
REM 05.administrativeRoles_name_PUT.bat [MENU...]
REM
REM   MENU  the menus the role opens, each one argument (default: Change Password
REM         and Audit Log)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The role is example_role, a limited role with the Change Password menu only.
REM   02.administrativeRoles_POST.bat creates it.
REM - PUT replaces the whole list; 06.administrativeRoles_name_PATCH.bat adds one
REM   menu to it instead.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to edit the role, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role
SET ROLE_FILE=%TEMP%\role_%RANDOM%.json
SET BODY_FILE=%TEMP%\role_body_%RANDOM%.json

REM The menus, one argument each, joined with | for PowerShell
SET MENUS=
:next_menu
IF "%~1"=="" GOTO menus_done
IF DEFINED MENUS (SET "MENUS=%MENUS%|%~1") ELSE (SET "MENUS=%~1")
SHIFT
GOTO next_menu
:menus_done
IF NOT DEFINED MENUS SET "MENUS=Change Password|Audit Log"

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ROLE%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%ROLE_FILE%"
SET FOUND=
FOR /F "delims=" %%N IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:ROLE_FILE | ConvertFrom-Json).roleName } catch { }"') DO SET FOUND=%%N
IF NOT DEFINED FOUND (
    echo There is no role %ROLE%. Run 02.administrativeRoles_POST.bat first.
    IF EXIST "%ROLE_FILE%" DEL "%ROLE_FILE%"
    EXIT /B 1
)

REM The whole role, without the read-only links, with the new menus
powershell -NoProfile -Command "$r = Get-Content -Raw $env:ROLE_FILE | ConvertFrom-Json; $r.menus = @($env:MENUS -split '\|'); $r.PSObject.Properties.Remove('metadata'); $r | ConvertTo-Json -Compress -Depth 10 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting the menus of %ROLE% to: %MENUS:|=, %
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ROLE%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%ROLE_FILE%" DEL "%ROLE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
