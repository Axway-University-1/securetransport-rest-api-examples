@echo off
REM ==============================================================================
REM Script Name: 07.applications_name_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes applications using the `/applications/{name}` endpoint.
REM It demonstrates:
REM - A direct DELETE request for a known application
REM - A conditional DELETE request after verifying existence
REM
REM Usage:
REM 07.applications_name_DELETE.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Application names with spaces must be URL-encoded.
REM - This cleans up the two applications 02.applications_POST.bat creates:
REM   "AccountFilePurge Application" and "HumanSystem Application". Earlier
REM   versions of this script named two different, pre-existing maintenance
REM   applications here instead - on a real server those are the built-in
REM   AuditLogMaint and TransferLogMaint housekeeping jobs, not test data, and
REM   deleting them would have been a real mistake rather than cleanup. Only
REM   ever point this at names this folder's own POST script created.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET NAME=AccountFilePurge Application
SET NAME=%NAME: =%%20%
echo Deleting application '%NAME%'...
curl -s -o nul -w "%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%NAME%" ^
-H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"

SET NAME=HumanSystem Application
SET NAME=%NAME: =%%20%
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%NAME%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET RESPONSE_CODE=%%C

IF "%RESPONSE_CODE%"=="200" (
    echo Application exists. Deleting application '%NAME%'...
    curl -s -o nul -w "%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications/%NAME%" ^
    -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"
    echo.
    echo Done
) ELSE (
    echo Application does not exist.
)
