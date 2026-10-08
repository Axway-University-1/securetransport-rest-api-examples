@echo off
REM ==============================================================================
REM Script Name: 06.administrativeRoles_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a menu to an administrative role, using the
REM `/administrativeRoles/{name}` endpoint with PATCH: a JSON Patch document that
REM appends to the menus list.
REM
REM Usage:
REM 06.administrativeRoles_name_PATCH.bat [MENU]
REM
REM   MENU  the menu to add (default File Tracking)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The role is example_role, a limited role with the Change Password menu only.
REM   02.administrativeRoles_POST.bat creates it.
REM - "/menus/-" is the end of the list: add appends there. Confirmed directly:
REM   the server does not keep the menus in order, so the new one may be
REM   read back anywhere in the list.
REM - Confirmed directly: a success answers 204, with no body. A menu the server does not know is 400 "List contains unsupported menu." and a role
REM   that does not exist 404 "No such administrative role."; the role is not changed by either.
REM - PowerShell is used to build the patch, in place of jq.
REM - Exit codes: 0 when the menu was added (204), 1 when the server refuses, 2 when the menu is empty (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role
SET "MENU=%~1"
IF "%MENU%"=="" SET MENU=File Tracking
SET BAD_ARGS=
IF NOT "%~2"=="" SET BAD_ARGS=yes
powershell -NoProfile -Command "if ($env:MENU.Trim() -eq '') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 SET BAD_ARGS=yes
IF DEFINED BAD_ARGS (
    echo Usage: 06.administrativeRoles_name_PATCH.bat [MENU]
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\role_patch_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\role_response_%RANDOM%.json

powershell -NoProfile -Command "ConvertTo-Json -Compress -InputObject @(@{ op='add'; path='/menus/-'; value=$env:MENU }) | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Adding the menu %MENU% to %ROLE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ROLE%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
