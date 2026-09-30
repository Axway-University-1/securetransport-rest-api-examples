@echo off
REM ==============================================================================
REM Script Name: 03.applications_name_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks if specific applications exist using the `/applications/{name}` endpoint.
REM It demonstrates:
REM - A HEAD request to verify existence of an application by name
REM - Conditional logic based on HTTP response code
REM
REM Usage:
REM 03.applications_name_HEAD.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Application names with spaces must be URL-encoded.
REM - Checks the two applications 02.applications_POST.bat creates. Run that
REM   script first, or both checks will report "does not exist".
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET NAME=AccountFilePurge Application
SET NAME=%NAME: =%%20%
echo Check if application with the name '%NAME%' exists...
curl -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"

SET NAME=HumanSystem Application
SET NAME=%NAME: =%%20%
echo.
echo Check if application with the name '%NAME%' exists...
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C

IF "%RESPONSE_CODE%"=="200" (
    echo Application exists.
) ELSE (
    echo Application does not exist.
)
