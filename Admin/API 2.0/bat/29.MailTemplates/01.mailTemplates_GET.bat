@echo off
REM ==============================================================================
REM Script Name: 01.mailTemplates_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the mail templates using the `/mailTemplates` endpoint: the
REM XHTML files SecureTransport builds its notification e-mails from.
REM It demonstrates:
REM - Counting them
REM - Listing them, one line each with the description
REM - Searching by name, and by description (both exact)
REM
REM Usage:
REM 01.mailTemplates_GET.bat [NAME [DESCRIPTION]]
REM
REM   NAME         a template's exact name, e.g. AdhocDefault.xhtml (optional)
REM   DESCRIPTION  an exact description (optional)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is {resultSet, result}; each entry has name, description
REM   (null when there is none) and metadata.links.self. The list is sorted by name, ignoring case.
REM - Confirmed directly: name= and description= are exact and case sensitive, with no * wildcard
REM   (name=Account* finds nothing), and resultSet.totalCount still counts every template.
REM - Confirmed directly: limit=-1 answers 400 "The limit should be a positive number or 0."; limit=0
REM   gives the default page size.
REM - The server ships templates of its own, for its notification e-mails: do not change them without
REM   keeping a copy (04.mailTemplates_name_GET.bat saves one).
REM - PowerShell is used to print one template per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there are more than two arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\mail_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
SET DESCRIPTION=%~2
IF NOT "%~3"=="" GOTO usage
SET SHOW=powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($t in $r.result) { $d = if ($null -eq $t.description) { '-' } else { $t.description }; '  {0}  {1}' -f $t.name, $d }"

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Mail templates: %%N

echo.
echo All of them: name, description:
SET "URL=%MAIN_URL%?limit=100"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
%SHOW%

IF NOT "%NAME%"=="" CALL :by_name
IF ERRORLEVEL 1 EXIT /B 1
IF NOT "%DESCRIPTION%"=="" CALL :by_description
IF ERRORLEVEL 1 EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The templates with the exact name in NAME
REM ------------------------------------------------------------------------------
:by_name
echo.
echo Named %NAME%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "name=%NAME%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
%SHOW%
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The templates with the exact description in DESCRIPTION
REM ------------------------------------------------------------------------------
:by_description
echo.
echo Described as %DESCRIPTION%:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "description=%DESCRIPTION%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
%SHOW%
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 01.mailTemplates_GET.bat [NAME [DESCRIPTION]]
EXIT /B 2
