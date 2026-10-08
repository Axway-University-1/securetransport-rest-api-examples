@echo off
REM ==============================================================================
REM Script Name: 01.businessUnits_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a business unit using the `/businessUnits` endpoint.
REM
REM Usage:
REM 01.businessUnits_POST.bat [NAME [BASE_FOLDER]]
REM
REM   NAME         the business unit (default Finance)
REM   BASE_FOLDER  its base folder, an absolute path (default /home/fin)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The baseFolder is the root under which the accounts of this business unit
REM   are created.
REM - Finance and /home/fin are the defaults, and 03 to 07 in this folder act on Finance too. A unit that
REM   exists is never changed: the server refuses a name or a base folder that is in use (see below) and the
REM   script exits 1. 07.businessUnits_name_DELETE.bat NAME removes the unit again.
REM - PowerShell is used to build the request body, in place of jq.
REM - Confirmed directly: a success is 201 with no body and the unit's address in `Location`. A name that exists
REM   is 400 (not 409) "Business unit name already exists. Business unit base folder is already in use or it is
REM   not valid.", a base folder that is not absolute 400 "Base folder is not valid: Folder name is not absolute:
REM   home/x", an empty name 400 "name cannot be empty", no baseFolder 400 "baseFolder must not be null". A name
REM   with a space is accepted (and needs encoding in a path: the other scripts of this folder do that).
REM - Exit codes: 0 when the unit was created (201), 1 when the server refuses, 2 when an argument is wrong
REM   (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET USAGE=Usage: 01.businessUnits_POST.bat [NAME [BASE_FOLDER]]
SET "NAME=%~1"
IF "%NAME%"=="" SET NAME=Finance
SET "BASE_FOLDER=%~2"
IF "%BASE_FOLDER%"=="" SET BASE_FOLDER=/home/fin
IF NOT "%~3"=="" (
    echo %USAGE%
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:NAME.Trim() -eq '') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo NAME must not be empty.
    echo %USAGE%
    EXIT /B 2
)
IF NOT "%BASE_FOLDER:~0,1%"=="/" (
    echo BASE_FOLDER must be an absolute path, starting with /, not %BASE_FOLDER%.
    echo %USAGE%
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\bu_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\bu_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\bu_headers_%RANDOM%.txt

powershell -NoProfile -Command "$b = [ordered]@{ name = $env:NAME; baseFolder = $env:BASE_FOLDER }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress))"

REM Create a Business Unit
echo Creating the business unit %NAME%, base folder %BASE_FOLDER%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
EXIT /B 0
