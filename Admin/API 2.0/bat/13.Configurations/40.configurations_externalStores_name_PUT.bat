@echo off
REM ==============================================================================
REM Script Name: 40.configurations_externalStores_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces an external store, using the
REM `/configurations/externalStores/{externalStoreName}` endpoint with PUT: it
REM reads the store, changes how long the server waits for an answer
REM (readTimeout), and sends the whole store back.
REM
REM Usage:
REM 40.configurations_externalStores_name_PUT.bat SECONDS [NAME]
REM
REM   SECONDS  the new readTimeout
REM   NAME  the external store (default example_vault)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Changing a store clears the secrets the server cached from it.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to URL-encode the name and edit the store, in place of jq.
REM - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
REM   as the web server answers 400 to an encoded slash.
REM - The store is read first and the old readTimeout is printed, so that it can be put back with the same script. A store that cannot be read (HTTP
REM   other than 200) stops it with exit 1 and nothing is changed.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET "SECONDS_WAIT=%~1"
SET "NAME=%~2"
IF "%NAME%"=="" SET NAME=example_vault
ECHO %SECONDS_WAIT%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo Usage: 40.configurations_externalStores_name_PUT.bat SECONDS [NAME]
    EXIT /B 2
)
IF NOT "%NAME:/=%"=="%NAME%" (
    echo NAME must not hold a /: such a name cannot be addressed in a path.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json
SET CHECK_FIELD=readTimeout

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/externalStores/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
SET BEFORE=
IF "%HTTP_CODE%"=="200" FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.PSObject.Properties.Name -contains $env:CHECK_FIELD) { ([string]$r.($env:CHECK_FIELD)).ToLower() } } catch { }"') DO SET BEFORE=%%V
IF NOT DEFINED BEFORE (
    echo Could not read the external store %NAME% ^(HTTP %HTTP_CODE%^).
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
echo readTimeout of %NAME% is now %BEFORE%.
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $r.readTimeout = [int]$env:SECONDS_WAIT; $r | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Setting it to %SECONDS_WAIT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/externalStores/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
EXIT /B 0
