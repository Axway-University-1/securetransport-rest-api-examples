@echo off
REM ==============================================================================
REM Script Name: 05.mailTemplates_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a mail template, using the `/mailTemplates/{name}` endpoint
REM with PUT: it uploads an XHTML file as a multipart form.
REM
REM Usage:
REM 05.mailTemplates_name_PUT.bat NAME FILE [DESCRIPTION]
REM
REM   NAME         the template to replace. There is no default: name the one to change.
REM   FILE         the XHTML file to upload
REM   DESCRIPTION  the new description (default: the one it has now; "" clears it)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: PUT on a name that does not exist CREATES the template and answers 204,
REM   not the 404 the reference lists. The script looks the template up first, and stops if it is
REM   not there, so a mistyped name does not leave a new template behind.
REM - Confirmed directly: a PUT with no description sets it to null, so the script reads the current
REM   one and sends it again; an empty description makes it an empty string.
REM - Confirmed directly: as with POST, the uploaded file must be named *.xhtml (the script sends
REM   it under NAME) and its content is not checked.
REM - Keep a copy of a template of the server's before replacing it: 04.mailTemplates_name_GET.bat.
REM - PowerShell is used to URL-encode the name and read the description, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
SET FILE=%~2
IF "%NAME: =%"=="" GOTO bad_name
powershell -NoProfile -Command "if ($env:NAME -match '[/\\]') { exit 2 }"
IF ERRORLEVEL 2 GOTO bad_name
GOTO name_ok
:bad_name
echo NAME must not be blank, and must not hold a / or a \: %NAME%
EXIT /B 2
:name_ok
IF NOT EXIST "%FILE%" (
    echo Usage: 05.mailTemplates_name_PUT.bat NAME FILE [DESCRIPTION]
    EXIT /B 2
)
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\mail_put_%RANDOM%.json
SET LOOKUP_FILE=%TEMP%\mail_lookup_%RANDOM%.json
SET DESCRIPTION=

REM PUT creates a template that does not exist, so look first
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="404" (
    echo There is no mail template %NAME% to replace.
    EXIT /B 1
)
IF NOT [%3]==[] (
    SET DESCRIPTION=%~3
    GOTO have_description
)
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=description" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$d = (Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result[0].description; if ($null -ne $d) { $d }"') DO SET "DESCRIPTION=%%D"
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
:have_description

echo Replacing the mail template %NAME% with %FILE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ENCODED%" -H "accept: */*" -H "%REFERER_HEADER%" -F "file=@%FILE%;type=application/xhtml+xml;filename=%NAME%" --form-string "description=%DESCRIPTION%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
