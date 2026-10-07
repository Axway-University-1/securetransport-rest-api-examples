@echo off
REM ==============================================================================
REM Script Name: 03.mailTemplates_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a mail template exists, using the
REM `/mailTemplates/{name}` endpoint with HEAD: 200 when it does, 404 when it
REM does not.
REM
REM Usage:
REM 03.mailTemplates_name_HEAD.bat [NAME]
REM
REM   NAME  the template (default example_mail.xhtml, which 02.mailTemplates_POST.bat
REM         creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the name is case sensitive (EXAMPLE_MAIL.xhtml is 404 where
REM   example_mail.xhtml is 200), and the 404 has an HTML body, not JSON.
REM - PowerShell is used to URL-encode the name, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_mail.xhtml
IF "%NAME: =%"=="" GOTO bad_name
powershell -NoProfile -Command "if ($env:NAME -match '[/\\]') { exit 2 }"
IF ERRORLEVEL 2 GOTO bad_name
GOTO name_ok
:bad_name
echo NAME must not be blank, and must not hold a / or a \: %NAME%
EXIT /B 2
:name_ok
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The mail template %NAME% exists.
) ELSE (
    echo The mail template %NAME% does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
