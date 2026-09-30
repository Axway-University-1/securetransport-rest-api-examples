@echo off
REM ==============================================================================
REM Script Name: 06.accounts_name_PATCH_with_file.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs a partial update to an account using the
REM `/accounts/{name}` endpoint, reading the PATCH body from a file instead of
REM building it on the command line.
REM It demonstrates:
REM - Keeping the request body in a separate, reusable JSON file
REM - Reading a value out of that file to report what is being changed
REM - Checking the HTTP response code instead of printing the whole response
REM
REM Usage:
REM 06.accounts_name_PATCH_with_file.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The 06.patch_body folder holds one file per example change. Point
REM   PATCH_FILE at whichever one you want to apply.
REM - A successful PATCH returns 204 with no response body.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET PATCH_FILE=06.patch_body\stPatchAccount.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

IF NOT EXIST "%PATCH_FILE%" (
    echo Patch body not found: %PATCH_FILE%
    EXIT /B 1
)

REM Read the path being changed out of the patch body, just for the message below
FOR /F "tokens=*" %%P IN ('powershell -Command "(Get-Content ''%PATCH_FILE%'' -Raw | ConvertFrom-Json).path"') DO SET ELEMENT_TO_BE_CHANGED=%%P

echo Changing '%ELEMENT_TO_BE_CHANGED%' of account '%ACCOUNT%'...
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%PATCH_FILE%"') DO SET HTTP_CODE=%%C

IF "%HTTP_CODE%"=="204" (
    echo Account '%ACCOUNT%' has been changed successfully.
) ELSE (
    echo Account '%ACCOUNT%' update failed.
    echo HTTP Code: %HTTP_CODE%
)
