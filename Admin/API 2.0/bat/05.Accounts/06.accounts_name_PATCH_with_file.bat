@echo off
REM ==============================================================================
REM Script Name: 06.accounts_name_PATCH_with_file.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs a partial update to an account using the
REM `/accounts/{name}` endpoint, reading the PATCH body from a file instead of
REM building it on the command line.
REM It demonstrates:
REM - Keeping the request body in a separate, reusable JSON file
REM - Printing what the paths of that file hold now, so that the change can be put back
REM - Checking the HTTP response code instead of printing the whole response
REM
REM Usage:
REM 06.accounts_name_PATCH_with_file.bat [NAME [PATCH_FILE]]
REM
REM   NAME        the account (default example_user, the one 02.accounts_POST.bat creates)
REM   PATCH_FILE  a JSON Patch body: a list of operations (default 06.patch_body/stPatchAccount.json, next to the script)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The 06.patch_body folder holds one file per example change. Give the one you want as the second argument. A file that is missing, or is not a list of
REM   operations with an `op` and a `path` each, is refused with exit 2 and nothing is sent.
REM - 06.patch_body/README.md says the same, next to the files (a JSON file cannot carry a comment).
REM - The samples are not all harmless anywhere. stPatchAccount.json (the default) and stPatchAccountContacts.json add a contact, stPatchAccountNotes.json sets the notes and
REM   stPatchAccountForcePasswordChange.json turns forcePasswordChange off: they work on any user account. stPatchAccountBU.json names things that exist only in one
REM   environment: it moves the account into the business unit `Pippin` and sets the home folder to `/usrdata/BU/Pippin/t3`, so it is refused (404
REM   "Business unit with name Pippin not found or not accessible.") on a server without that unit, and it must be adapted to your own business unit and base folder before it is used.
REM   The contact samples carry made up addresses (a@b.com1 and a22@1b.com1): replace them with real ones if the contact is to be used.
REM - Before it changes anything the script reads the account and prints what each path of the file holds now (null when the path is not there yet, as with the end of an array).
REM   Taking an added contact out again is a `remove` of its index (see 06.accounts_name_PATCH.bat); for a `replace`, send the old value back.
REM - PowerShell is used to read the paths and what they hold now, in place of jq.
REM - Confirmed directly: a success is 204 with no body; a business unit that does not exist is 404; a path that does not exist is 400 `Missing field "nope"`.
REM - Exit codes: 0 when the server answered 204, 1 when the account cannot be read or the server refuses, 2 when the body file is missing or is not a JSON Patch (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET PATCH_FILE=%~2
REM %~dp0 is the folder of this script, and 06.patch_body follows it
IF "%PATCH_FILE%"=="" SET PATCH_FILE=%~dp006.patch_body\stPatchAccount.json
SET USAGE=Usage: 06.accounts_name_PATCH_with_file.bat [NAME [PATCH_FILE]]
IF NOT "%~3"=="" GOTO usage
IF NOT EXIST "%PATCH_FILE%" (
    echo The patch body %PATCH_FILE% is not a file.
    GOTO usage
)
powershell -NoProfile -Command "try { $p = @(Get-Content -Raw $env:PATCH_FILE | ConvertFrom-Json); if ($p.Count -gt 0 -and @($p | Where-Object { $_.op -and $_.path }).Count -eq $p.Count) { exit 0 } else { exit 1 } } catch { exit 1 }"
IF ERRORLEVEL 1 (
    echo %PATCH_FILE% is not a JSON Patch: a list of operations, each with an op and a path.
    GOTO usage
)
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json

echo Reading the account %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%NAME_URI%" --data-urlencode "fields=type" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %NAME%: HTTP %HTTP_CODE%
    GOTO refused
)
FOR /F "delims=" %%T IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).type"') DO SET ACCOUNT_TYPE=%%T
REM Fields that belong to one account type, like addressBookSettings, are only returned with the type
curl -s -o "%RESPONSE_FILE%" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%NAME_URI%" --data-urlencode "type=%ACCOUNT_TYPE%" -H "accept: application/json" -H "%REFERER_HEADER%"

REM What each path of the patch holds now: "-" at the end of a path is a new element of an array, which has no value yet
echo What the paths hold now:
powershell -NoProfile -Command "$a = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($op in @(Get-Content -Raw $env:PATCH_FILE | ConvertFrom-Json)) { $cur = $a; foreach ($seg in $op.path.TrimStart('/').Split('/')) { if ($null -eq $cur -or $seg -eq '-') { $cur = $null } elseif ($cur -is [array]) { if ($seg -match '^[0-9]+$' -and [int]$seg -lt $cur.Count) { $cur = $cur[[int]$seg] } else { $cur = $null } } else { $cur = $cur.$seg } }; '  {0}: {1}' -f $op.path, (ConvertTo-Json -InputObject $cur -Compress -Depth 10) }"

FOR /F "delims=" %%P IN ('powershell -NoProfile -Command "(@(Get-Content -Raw $env:PATCH_FILE | ConvertFrom-Json) | ForEach-Object { $_.path }) -join ([char]44 + [char]32)"') DO SET ELEMENT_TO_BE_CHANGED=%%P
echo Changing '%ELEMENT_TO_BE_CHANGED%' of account '%NAME%'...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%NAME_URI%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%PATCH_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%

IF "%HTTP_CODE%"=="204" (
    echo Account '%NAME%' has been changed successfully.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 0
)
echo Account '%NAME%' update failed.
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
