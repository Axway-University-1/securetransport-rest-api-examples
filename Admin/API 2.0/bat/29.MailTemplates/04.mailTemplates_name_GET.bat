@echo off
REM ==============================================================================
REM Script Name: 04.mailTemplates_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads a mail template, using the `/mailTemplates/{name}` endpoint: its
REM description, and the XHTML file itself, saved to a local file.
REM
REM Usage:
REM 04.mailTemplates_name_GET.bat [NAME [OUTPUT]]
REM
REM   NAME    the template (default example_mail.xhtml)
REM   OUTPUT  the file to write (default: NAME, in the current folder)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is the file itself, application/xhtml+xml, with a
REM   Content-Disposition of attachment; there is no JSON form (an accept of application/json still
REM   answers the XHTML). The description is only in the list, so the script asks for it there, by
REM   exact name. An unknown name answers 404 with a JSON message.
REM - Keep the file this saves before replacing one of the server's own templates with
REM   05.mailTemplates_name_PUT.bat.
REM - PowerShell is used to URL-encode the name and print the description and the error, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_mail.xhtml
SET OUTPUT=%~2
IF "%OUTPUT%"=="" SET OUTPUT=%NAME%
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
SET RESPONSE_FILE=%OUTPUT%
SET LOOKUP_FILE=%TEMP%\mail_lookup_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=description" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$d = (Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result[0].description; if ($null -eq $d) { '-' } else { $d }"') DO echo Description: %%D
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%OUTPUT%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/xhtml+xml" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    FOR %%S IN ("%OUTPUT%") DO echo Written to %OUTPUT%, %%~zS bytes.
) ELSE (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%OUTPUT%" DEL "%OUTPUT%"
    EXIT /B 1
)
