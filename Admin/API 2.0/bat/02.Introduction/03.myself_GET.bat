@echo off
REM ==============================================================================
REM Script Name: 03.myself_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script queries the API to retrieve information about the current user.
REM It performs two GET requests:
REM   1. To fetch full user details.
REM   2. To extract the last password change time from the response.
REM
REM Usage:
REM call 03_myself_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - The script uses basic authentication and filters JSON output using findstr.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

REM Query the API to get full user information
echo.
echo Querying the API to get information about the current user...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"

REM Query again and filter for last password change time
echo.
echo Querying the API again and filtering the response to find the last password change time...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" | findstr "lastPasswordChangeTime"
