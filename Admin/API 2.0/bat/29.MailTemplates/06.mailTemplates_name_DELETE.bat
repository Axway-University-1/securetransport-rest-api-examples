@echo off
REM ==============================================================================
REM Script Name: 06.mailTemplates_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes a mail template, using the `/mailTemplates/{name}` endpoint.
REM
REM Usage:
REM 06.mailTemplates_name_DELETE.bat NAME
REM
REM   NAME  the template. There is no default: name the one to delete.
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is 204; a name that does not exist answers 404 "Mail Template ...
REM   not found." The name is case sensitive.
REM - NOT run on the lab against one of the server's own templates (AdhocDefault.xhtml and the
REM   like): the notification e-mails are built from them. Save a copy first with
REM   04.mailTemplates_name_GET.bat.
REM - PowerShell is used to URL-encode the name and print the reason, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
IF "%NAME%"=="" (
    echo Usage: 06.mailTemplates_name_DELETE.bat NAME
    EXIT /B 2
)
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
SET RESPONSE_FILE=%TEMP%\mail_delete_%RANDOM%.json

echo Deleting the mail template %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
