@echo off
REM ==============================================================================
REM Script Name: 04.myself_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes the password of the administrator it logs in as, using the `/myself`
REM endpoint with PATCH: a JSON Patch document that replaces `/passwordCredentials/password`.
REM It demonstrates:
REM - Reading the new password from the environment, never from the file or an argument
REM - Building the JSON Patch body with jq, so any character in the password stays valid JSON
REM - Checking the HTTP code: 204 is the only success
REM
REM Usage:
REM SET ST_NEW_PASSWORD=the new password
REM 04.myself_PATCH.bat
REM
REM   ST_NEW_PASSWORD  the new password, from the environment (an argument would show in the process list).
REM                    Without it the script prints this usage, sends NOTHING and exits 2
REM
REM Risk: config - changes the password of the administrator every example logs in as; every later call needs the new one
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - THIS CHANGES THE PASSWORD OF THE ADMINISTRATOR IN ST_USER, the one every example logs in as. From the next call on
REM   every example needs the new password: change it in `set_variables.local.bat` (or set_variables.local.bat) as soon as this
REM   has run. Run it against a throwaway administrator, as check 13 does, unless that is what you want.
REM - The old password is never known to the script, so it cannot print it. To put it back, run this script again with the old
REM   password in ST_NEW_PASSWORD, logging in with the new one.
REM - PowerShell is used to build the request body, in place of jq.
REM - The password is never printed. Nothing is sent without ST_NEW_PASSWORD (exit 2).
REM - Confirmed directly: a success is 204 with no body, and the old password stops working at once (401) while the new one works at
REM   once. The same password again is 204 too. The lab accepted a one-letter password (no complexity rule refused it), and an empty
REM   one is 400 "password cannot be empty". Only `/passwordCredentials/password` and `/preferredFileTrackingColumns` can be patched on
REM   `/myself` (any other path is 400 "Patch operation is allowed only on fields ..."); a body that is not a list is 400 "Incorrect JSON
REM   format"; a wrong current password is a plain 401 "Authentication required."
REM - Exit codes: 0 when the server answered 204, 1 when it refuses, 2 when ST_NEW_PASSWORD is not set (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself
IF NOT DEFINED ST_NEW_PASSWORD (
    echo This changes the password of %ST_USER%, the administrator every example logs in as.
    echo Nothing was sent. To go on, set ST_NEW_PASSWORD to the new password.
    echo Usage: SET ST_NEW_PASSWORD=the new password ^& 04.myself_PATCH.bat
    EXIT /B 2
)

SET BODY_FILE=%TEMP%\myself_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\myself_response_%RANDOM%.txt

powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/passwordCredentials/password'; value = $env:ST_NEW_PASSWORD }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"

echo Changing the password of %ST_USER%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
echo The password of %ST_USER% is changed. Every later call needs the new one: put it in set_variables.local.bat.
