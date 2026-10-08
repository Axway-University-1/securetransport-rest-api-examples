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
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The role is example_role, a limited role with the Change Password menu only.
REM - A limited role (isLimited) can only manage what its own administrators
REM   create. isBounceAllowed lets it restart the server.
REM - menus are the Admin UI's own names: User Accounts, File Tracking, Audit
REM   Log, Certificates and so on; the API reference lists them all.
REM - 07.administrativeRoles_name_DELETE.bat removes it again.
REM - PowerShell is used to build the request body, in place of jq.
REM - Confirmed directly: a success is 201 with no body and the role's address in `Location`. A role that exists is 409 "Administrative role with the
REM   same name already exist on the server." (nothing is changed), and a menu the server does not know 400 "List contains unsupported menu.".
REM - Exit codes: 0 when the role was created (201), 1 when the server refuses.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrativeRoles
SET ROLE=example_role
SET BODY_FILE=%TEMP%\role_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\role_response_%RANDOM%.json

powershell -NoProfile -Command "$b = [ordered]@{ roleName = $env:ROLE; isLimited = $true; isBounceAllowed = $false; menus = @('Change Password') }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Creating the role %ROLE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
