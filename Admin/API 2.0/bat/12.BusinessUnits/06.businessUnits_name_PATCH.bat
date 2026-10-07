@echo off
REM ==============================================================================
REM Script Name: 06.businessUnits_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a business unit, using the
REM `/businessUnits/{name}` endpoint with PATCH: a JSON Patch document that sets
REM whether the accounts in it may collaborate on shared folders
REM (sharedFoldersCollaborationAllowed). Unlike PUT
REM (05.businessUnits_name_PUT.bat), it sends only what changes.
REM
REM Usage:
REM 06.businessUnits_name_PATCH.bat NAME [VALUE]
REM
REM   NAME   the business unit
REM   VALUE  the new sharedFoldersCollaborationAllowed, true or false (default
REM          true)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put it back with. A new unit has null: the
REM   server's default applies.
REM - Confirmed directly: replace works on a property that is null; a success
REM   answers 204, with no body.
REM - PowerShell is used to URL-encode the name and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 06.businessUnits_name_PATCH.bat NAME [VALUE]
    EXIT /B 2
)
SET VALUE=%~2
IF "%VALUE%"=="" SET VALUE=true
IF NOT "%VALUE%"=="true" IF NOT "%VALUE%"=="false" (
    echo VALUE is true or false, not %VALUE%.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET BU_FILE=%TEMP%\bu_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%?fields=sharedFoldersCollaborationAllowed" -H "accept: application/json" -H "%REFERER_HEADER%" > "%BU_FILE%"
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "$v = (Get-Content -Raw $env:BU_FILE | ConvertFrom-Json).sharedFoldersCollaborationAllowed; if ($null -eq $v) { 'null' } else { ([string]$v).ToLower() }"') DO echo sharedFoldersCollaborationAllowed of %NAME% is now %%V.

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/sharedFoldersCollaborationAllowed\",\"value\":%VALUE%}]"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BU_FILE%" DEL "%BU_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
