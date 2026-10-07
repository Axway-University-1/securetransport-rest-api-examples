@echo off
REM ==============================================================================
REM Script Name: 03.icapServers_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether an ICAP server exists using the `/icapServers/{name}`
REM endpoint with HEAD: 200 when it does, 404 when it does not.
REM
REM Usage:
REM 03.icapServers_name_HEAD.bat [NAME]
REM
REM   NAME  the server (default example_icap)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The name goes into the path URL-encoded once, with jq's @uri.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/icapServers
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_icap
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET ENCODED=%%E

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The ICAP server %NAME% exists.
) ELSE (
    echo The ICAP server %NAME% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
