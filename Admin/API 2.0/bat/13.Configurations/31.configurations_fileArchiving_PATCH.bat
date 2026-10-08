@echo off
REM ==============================================================================
REM Script Name: 31.configurations_fileArchiving_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes how long archived files are kept, using the
REM `/configurations/fileArchiving` endpoint with PATCH.
REM
REM Usage:
REM 31.configurations_fileArchiving_PATCH.bat DAYS
REM
REM   DAYS  delete archived files older than this many days
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put back with.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to read the value, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET DAYS=%~1
ECHO %DAYS%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo Usage: 31.configurations_fileArchiving_PATCH.bat DAYS
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/fileArchiving" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Archived files are now deleted after {0} {1}.' -f $r.deleteFilesOlderThan, $r.deleteFilesOlderThanUnit"

powershell -NoProfile -Command "ConvertTo-Json -Compress -Depth 5 -InputObject @(@{op='replace'; path='/deleteFilesOlderThan'; value=[int]$env:DAYS}, @{op='replace'; path='/deleteFilesOlderThanUnit'; value='days'}) | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Setting it to %DAYS% days...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/fileArchiving" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
