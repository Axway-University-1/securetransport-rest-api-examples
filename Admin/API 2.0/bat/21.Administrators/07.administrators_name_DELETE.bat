@echo off
REM ==============================================================================
REM Script Name: 07.administrators_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes an administrator, using the `/administrators/{name}`
REM endpoint.
REM
REM Usage:
REM 07.administrators_name_DELETE.bat [ADMIN]
REM
REM   ADMIN  the login name (default example_admin, which 02.administrators_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It deletes example_admin, which 02.administrators_POST.bat creates. Only ever
REM   point it at an administrator you created: any can be named, and the delete cannot be undone.
REM - Its API keys go with it.
REM - THE ADMINISTRATOR YOU LOG IN AS (ST_USER) IS NEVER DELETED: the script refuses that name, whatever its case, with exit 2 before sending anything. Confirmed
REM   directly that the server refuses it too: an administrator that deletes itself gets 400 "Administrator cannot be deleted." (tried with a throwaway one).
REM - The administrator is read first and what it is (role, parent, locked) is printed, so that it can be created again with 02.administrators_POST.bat. One
REM   that cannot be read (404 "Admin not found - X") stops the script with exit 1 and nothing is deleted.
REM - PowerShell is used to URL-encode the login name and read the administrator, in place of jq.
REM - Confirmed directly: a delete is 204 with no body. An administrator that is not there is 404 on the read and on the delete.
REM - Exit codes: 0 when the administrator was deleted (204), 1 when the server refuses or it cannot be read, 2 when the name is empty, is the one logged
REM   in as, or there are too many arguments (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/administrators
SET "ADMIN=%~1"
IF "%ADMIN%"=="" SET ADMIN=example_admin
SET BAD_ARGS=
IF NOT "%~2"=="" SET BAD_ARGS=yes
powershell -NoProfile -Command "if ($env:ADMIN.Trim() -eq '') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 SET BAD_ARGS=yes
IF DEFINED BAD_ARGS (
    echo Usage: 07.administrators_name_DELETE.bat [ADMIN]
    EXIT /B 2
)
IF /I "%ADMIN%"=="%ST_USER%" (
    echo %ADMIN% is the administrator this script logs in as. It is never deleted.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:ADMIN)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\admin_response_%RANDOM%.json

REM Read it first, to say what is being deleted
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the administrator %ADMIN% ^(HTTP %HTTP_CODE%^), so nothing was deleted.
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = $a.parent; if (-not $p) { $p = '-' }; 'Deleting the administrator {0} (role {1}, created by {2}, locked {3})...' -f $env:ADMIN, $a.roleName, $p, ([string]$a.locked).ToLower()"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
