@echo off
REM ==============================================================================
REM Script Name: 01.configurations_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes a Server Configuration Option using the
REM `/configurations/options/{name}` endpoint with the PATCH method.
REM
REM Usage:
REM 01.configurations_PATCH.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An option holds a list of values, so the path targets an index:
REM   "/values/0" is the first value.
REM - Changing a Server Configuration Option affects the whole server.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET OPTION=AddressBook.Enabled

echo Setting %OPTION% to true...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations/options/%OPTION%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{\"op\":\"replace\",\"path\":\"/values/0\",\"value\":\"true\"}]"
