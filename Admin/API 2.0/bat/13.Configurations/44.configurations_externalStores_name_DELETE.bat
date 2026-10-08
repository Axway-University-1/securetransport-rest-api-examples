@echo off
REM ==============================================================================
REM Script Name: 44.configurations_externalStores_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes an external store, using the
REM `/configurations/externalStores/{externalStoreName}` endpoint.
REM
REM Usage:
REM 44.configurations_externalStores_name_DELETE.bat [NAME]
REM
REM   NAME  the external store (default example_vault)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Anything that fetches its secrets from the store stops working: only ever
REM   point it at a store you created.
REM - The store is read first and what is deleted is printed (its address and cache timeout), so that it can be added again with
REM   38.configurations_externalStores_POST.bat. A store that cannot be read stops the script (exit 1) before anything is deleted.
REM - PowerShell is used to URL-encode the name and read the store, in place of jq.
REM - The name is URL-encoded into the path (a name with a space works); one with a / is refused with exit 2 (nothing is sent),
REM   as the web server answers 400 to an encoded slash.
REM - Confirmed directly: a delete is 204 with no body. A name that is not a store is 400 (not 404) on the delete, "Cannot delete External Store
REM   with name: X. Cannot find External Store or External Store configuration is not accessible", and 404 on the read.
REM - Exit codes: 0 when the store was deleted (204), 1 when the server refuses or the store cannot be read, 2 when the name is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET "NAME=%~1"
IF "%NAME%"=="" SET NAME=example_vault
IF NOT "%NAME:/=%"=="%NAME%" (
    echo NAME must not hold a /: such a name cannot be addressed in a path.
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json

REM Read it first, to say what is being deleted
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/externalStores/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the external store %NAME% ^(HTTP %HTTP_CODE%^), so nothing was deleted.
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; 'Deleting the external store {0} ({1}{2}, cached {3}s)...' -f $env:NAME, $r.baseUrl, $r.uri, $r.cacheTimeout"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/externalStores/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
