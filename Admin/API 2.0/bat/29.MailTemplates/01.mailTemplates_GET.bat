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
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/mailTemplates
SET NAME=%~1
SET DESCRIPTION=%~2
SET RESPONSE_FILE=%TEMP%\mail_%RANDOM%.json
SET SHOW=powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($t in $r.result) { $d = if ($null -eq $t.description) { '-' } else { $t.description }; '  {0}  {1}' -f $t.name, $d }"

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Mail templates: %%N

echo.
echo All of them: name, description:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=100" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
%SHOW%

IF "%NAME%"=="" GOTO by_description
echo.
echo Named %NAME%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
%SHOW%

:by_description
IF "%DESCRIPTION%"=="" GOTO done
echo.
echo Described as %DESCRIPTION%:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "description=%DESCRIPTION%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
%SHOW%
:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
