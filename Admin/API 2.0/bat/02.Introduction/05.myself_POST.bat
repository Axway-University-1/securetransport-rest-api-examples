@echo off
REM ==============================================================================
REM Script Name: 05.myself_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script performs a POST request to the `/myself` endpoint, which is
REM related to user authentication. It initiates a session or validates credentials
REM depending on the API implementation.
REM
REM Usage:
REM call 05_myself_POST.bat
REM
REM Notes:
REM - For complete documentation, refer to folder 01.Authentication.
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM ==============================================================================

call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/myself" -H "accept: application/json" -H "%REFERER_HEADER%"
