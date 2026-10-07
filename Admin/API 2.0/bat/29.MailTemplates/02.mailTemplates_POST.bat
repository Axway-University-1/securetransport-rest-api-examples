@echo off
REM ==============================================================================
REM Script Name: 02.mailTemplates_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script adds a mail template using the `/mailTemplates` endpoint: it uploads an
REM XHTML file as a multipart form, with a name and a description.
REM
REM Usage:
REM 02.mailTemplates_POST.bat [NAME [FILE [DESCRIPTION]]]
REM
REM   NAME         the template's name, ending in .xhtml (default example_mail.xhtml)
REM   FILE         the XHTML file to upload (default: a small one the script writes)
REM   DESCRIPTION  its description (default: Created by 29.MailTemplates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: name and file are both required (400 "Name can't be empty." and
REM   "File can't be empty."). The body must be a multipart form: JSON answers 415.
REM - Confirmed directly: the name must end in .xhtml (400 "Valid Mail Template name is not empty and
REM   with file extension xhtml."). It is case sensitive: example_mail.xhtml and EXAMPLE_MAIL.xhtml
REM   are two templates. A name that exists answers 409 "Template with name ... already exists." A name
REM   of 300 characters answers 400 "Database error creating mail template"; a space is fine.
REM - Confirmed directly: a name with a / in it is accepted by POST, but the entry can then not be addressed by any path (%2F answers 400) and so not deleted. The script refuses a / or \ in a name.
REM - Confirmed directly: although the reference says the uploaded file's own name is ignored, the
REM   server checks it: a file not named *.xhtml answers 400 "Invalid mail template file, only .xhtml
REM   name extensions are supported." The script sends the file under the template's name, so any
REM   local file will do. The content is not checked at all: an empty file, or plain text, is accepted.
REM - Confirmed directly: the answer is 201, the address in Location, and no body. A description left
REM   out reads back as null.
REM - A mail template is plain XHTML; the ones the server ships carry the Velocity settings of the
REM   e-mail in comments, e.g. <!-- #set( $subject = "...") -->.
REM - PowerShell is used to print the error, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_mail.xhtml
SET FILE=%~2
SET SAMPLE_FILE=
IF [%3]==[] (SET DESCRIPTION=Created by 29.MailTemplates) ELSE (SET DESCRIPTION=%~3)
IF "%NAME: =%"=="" GOTO bad_name
powershell -NoProfile -Command "if ($env:NAME -match '[/\\]') { exit 2 }"
IF ERRORLEVEL 2 GOTO bad_name
GOTO name_ok
:bad_name
echo NAME must not be blank, and must not hold a / or a \: %NAME%
EXIT /B 2
:name_ok
IF NOT "%NAME:~-6%"==".xhtml" (
    echo NAME must end in .xhtml: %NAME%
    EXIT /B 2
)
IF NOT "%FILE%"=="" GOTO have_file_arg
SET SAMPLE_FILE=%TEMP%\mail_sample_%RANDOM%.xhtml
powershell -NoProfile -Command "[IO.File]::WriteAllText($env:SAMPLE_FILE, '<?xml version=\"1.0\" encoding=\"UTF-8\"?>' + [Environment]::NewLine + '<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title></title></head><body><p>$MESSAGE</p></body></html>' + [Environment]::NewLine)"
SET FILE=%SAMPLE_FILE%
GOTO file_ok
:have_file_arg
IF NOT EXIST "%FILE%" (
    echo There is no file %FILE%.
    EXIT /B 2
)
:file_ok
SET RESPONSE_FILE=%TEMP%\mail_response_%RANDOM%.json
SET HEADERS_FILE=%TEMP%\mail_headers_%RANDOM%.txt

echo Adding the mail template %NAME% from %FILE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -F "file=@%FILE%;type=application/xhtml+xml;filename=%NAME%" --form-string "name=%NAME%" --form-string "description=%DESCRIPTION%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%SAMPLE_FILE%" DEL "%SAMPLE_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO SET LOCATION=%%B
powershell -NoProfile -Command "'Its address ends: ' + $env:LOCATION.Trim().Substring($env:LOCATION.Trim().LastIndexOf([char]47) + 1)"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
