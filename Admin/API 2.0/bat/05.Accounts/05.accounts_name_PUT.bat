@echo off
REM ==============================================================================
REM Script Name: 05.accounts_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes the uid of an account, using the `/accounts/{name}` endpoint with the PUT method.
REM It demonstrates the easiest way to update more than one property of an object:
REM 1. GET the object's content
REM 2. edit the parts you want with jq
REM 3. PUT the whole object back
REM
REM Usage:
REM 05.accounts_name_PUT.bat [NAME [NEW_UID]]
REM
REM   NAME     the account (default example_user, the one 02.accounts_POST.bat creates)
REM   NEW_UID  the new uid, a whole number (default 1111)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PUT replaces the entire object, so all required fields must be preserved: the script sends back the object it read, with only the uid changed.
REM - It prints the old uid, and the command that puts it back, before it changes anything. The 41733 that 02.accounts_POST.bat gives is on purpose: see its Notes.
REM - PowerShell is used to is used to edit the retrieved JSON. Editing it with jq rather than with a text substitution targets the exact field and always produces valid JSON, in place of jq.
REM   No file is written: the answer is kept in a variable.
REM - Confirmed directly: a success is 204 with no body, also when the object is sent back exactly as it was read (the `metadata` links included). A name that is not an
REM   account is 404 on the read, so nothing is sent.
REM - Exit codes: 0 when the server answered 204, 1 when the account cannot be read or the server refuses, 2 when NEW_UID is not a whole number (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET NEW_UID=%~2
IF "%NEW_UID%"=="" SET NEW_UID=1111
SET USAGE=Usage: 05.accounts_name_PUT.bat [NAME [NEW_UID]]   with NEW_UID a whole number, 1111 when left out
IF NOT "%~3"=="" GOTO usage
powershell -NoProfile -Command "if ($env:NEW_UID -match '^[0-9]{1,9}$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\account_body_%RANDOM%.json

echo Getting the account %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %NAME%: HTTP %HTTP_CODE%
    GOTO refused
)
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'The uid of {0} is now {1}.' -f $env:NAME, $o.uid; 'To put it back: 05.accounts_name_PUT.bat {0} {1}' -f $env:NAME, $o.uid"

echo Changing the uid to %NEW_UID%...
powershell -NoProfile -Command "$o = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $o.uid = $env:NEW_UID; [IO.File]::WriteAllText($env:BODY_FILE, ($o | ConvertTo-Json -Depth 100 -Compress))"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" GOTO refused
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
