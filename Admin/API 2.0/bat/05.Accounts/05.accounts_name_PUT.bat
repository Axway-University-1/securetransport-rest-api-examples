@echo off
REM ==============================================================================
REM Script Name: 05.accounts_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script updates an account using the `/accounts/{name}` endpoint with the
REM PUT method, which is the easiest way to update more than one property at once.
REM It demonstrates:
REM 1. GET to retrieve the object's content
REM 2. PowerShell to modify the parts we want
REM 3. PUT to update the object's content
REM
REM Usage:
REM 05.accounts_name_PUT.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PUT replaces the entire object, so all required fields must be preserved.
REM - The JSON is edited with PowerShell rather than with a text substitution, so
REM   that the exact field is targeted and the result is always valid JSON.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=UserAccount
SET NEW_UID=1111
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

echo Getting the account %ACCOUNT%...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" > result.json

echo Changing the uid to %NEW_UID%...
powershell -Command "$o = Get-Content result.json -Raw | ConvertFrom-Json; $o.uid = '%NEW_UID%'; $o | ConvertTo-Json -Depth 100 | Set-Content new_result.json"

curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d @new_result.json

REM Remove the temporary API responses
IF EXIST result.json DEL result.json
IF EXIST new_result.json DEL new_result.json
