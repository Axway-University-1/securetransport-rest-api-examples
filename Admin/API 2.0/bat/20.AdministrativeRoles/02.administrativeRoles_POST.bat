@echo off
REM ==============================================================================
REM Script Name: 02.administrativeRoles_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates an administrative role using the `/administrativeRoles`
REM endpoint: a name, and the Admin UI menus the role opens.
REM
REM Usage:
REM 02.administrativeRoles_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The role is example_role, a limited role with the Change Password menu only.
REM - A limited role (isLimited) can only manage what its own administrators
REM   create. isBounceAllowed lets it restart the server.
REM - menus are the Admin UI's own names: User Accounts, File Tracking, Audit
REM   Log, Certificates and so on; the API reference lists them all.
REM - 07.administrativeRoles_name_DELETE.bat removes it again.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role

echo Creating the role %ROLE%...
curl -s -o nul -w "HTTP %%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "{\"roleName\":\"%ROLE%\",\"isLimited\":true,\"isBounceAllowed\":false,\"menus\":[\"Change Password\"]}"
