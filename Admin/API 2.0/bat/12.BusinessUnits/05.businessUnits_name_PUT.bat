@echo off
REM ==============================================================================
REM Script Name: 05.businessUnits_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a business unit, using the `/businessUnits/{name}`
REM endpoint with PUT: it reads the unit, changes whether the accounts in it may
REM change their home folders (homeFolderModifyingAllowed), and sends the whole
REM unit back.
REM
REM Usage:
REM 05.businessUnits_name_PUT.bat NAME [VALUE]
REM
REM   NAME   the business unit
REM   VALUE  the new homeFolderModifyingAllowed, true or false (default true)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put it back with.
REM - metadata, the read-only links, is left out of what is sent.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to URL-encode the name and edit the unit, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 05.businessUnits_name_PUT.bat NAME [VALUE]
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
SET BODY_FILE=%TEMP%\bu_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%BU_FILE%"
SET BEFORE=
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $b = Get-Content -Raw $env:BU_FILE | ConvertFrom-Json; if ($b.name) { ([string]$b.homeFolderModifyingAllowed).ToLower() } } catch { }"') DO SET BEFORE=%%V
IF NOT DEFINED BEFORE (
    echo There is no business unit %NAME%.
    IF EXIST "%BU_FILE%" DEL "%BU_FILE%"
    EXIT /B 1
)
echo homeFolderModifyingAllowed of %NAME% is now %BEFORE%.
powershell -NoProfile -Command "$b = Get-Content -Raw $env:BU_FILE | ConvertFrom-Json; $b.homeFolderModifyingAllowed = ($env:VALUE -eq 'true'); $b.PSObject.Properties.Remove('metadata'); $b | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BU_FILE%" DEL "%BU_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
