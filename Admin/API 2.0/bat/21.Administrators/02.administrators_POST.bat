@echo off
REM ==============================================================================
REM Script Name: 02.administrators_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates an administrator using the `/administrators` endpoint: a
REM login name, a role, and a password.
REM
REM Usage:
REM [SET ADMIN_PASSWORD=the password of example_admin]
REM 02.administrators_POST.bat
REM
REM   ADMIN_PASSWORD  the password of example_admin, from the environment (optional): when it is not set, one is generated and printed
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The administrator is example_admin, with the role example_role: run
REM   20.AdministrativeRoles/02.administrativeRoles_POST.bat first.
REM   ADMIN_PASSWORD is read from the environment (export it first). It is never in the file: when it is not set, a password is generated (12 random
REM   letters and digits after a fixed beginning that satisfies a password policy) and printed once.
REM - Confirmed directly: parent - the administrator it is created under - is
REM   needed, though the API reference does not mark it required. Without it:
REM   400 "Please specify parent administrator". Here it is ST_USER.
REM - 07.administrators_name_DELETE.bat removes it again.
REM - PowerShell is used to build the body, in place of jq.
REM - Confirmed directly: a success is 201 with no body and the administrator's address in `Location`. An administrator that exists is 409 "Entry already
REM   exist.", a role that does not exist 400 "An admin role with the specified roleName not found.", an empty password 400 "The password cannot be empty.", and a
REM   name with a space 400 "Spaces are not allowed in an Administrator Name.". Nothing is created by a refusal.
REM - Exit codes: 0 when the administrator was created (201), 1 when the server refuses.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET ADMIN=example_admin
SET ROLE=example_role
SET BODY_FILE=%TEMP%\admin_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\admin_response_%RANDOM%.json

SET GENERATED=
IF NOT DEFINED ADMIN_PASSWORD (
    REM A generated password, written to a file by PowerShell and read back: a FOR /F command cannot hold single quotes
    powershell -NoProfile -Command "[IO.File]::WriteAllText($env:RESPONSE_FILE, 'Ex1!' + (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })))"
    SET /P ADMIN_PASSWORD=<"%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    SET GENERATED=yes
)

powershell -NoProfile -Command "$b = [ordered]@{ loginName = $env:ADMIN; roleName = $env:ROLE; parent = $env:ST_USER; localAuthentication = $true; passwordCredentials = [ordered]@{ password = $env:ADMIN_PASSWORD } }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

echo Creating the administrator %ADMIN%, role %ROLE%...
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
IF "%GENERATED%"=="yes" echo The password of %ADMIN% is %ADMIN_PASSWORD% ^(generated: it is not shown again^).
EXIT /B 0
