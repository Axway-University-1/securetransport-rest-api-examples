@echo off
REM ==============================================================================
REM Script Name: 05.applications_name_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script updates an application using the `/applications/{name}` endpoint.
REM It demonstrates:
REM - Retrieving the full application object
REM - Modifying the notes field with a timestamp
REM - Sending a PUT request to update the application
REM
REM Usage:
REM 05.applications_name_PUT.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PUT replaces the entire object, so all required fields must be preserved.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/applications
SET NAME=AccountFilePurge%%20Application

curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" > tmp.json

FOR /F %%D IN ('powershell -Command "Get-Date -Format o"') DO SET DATE=%%D
REM
REM Edit the retrieved object as an object rather than as text. This targets the
REM notes field itself and always produces valid JSON, which a regular
REM expression substitution cannot guarantee.
REM
powershell -Command ^
  "$json = Get-Content -Raw 'tmp.json' | ConvertFrom-Json; " ^
  "$json.notes = 'New note %DATE%'; " ^
  "$json | ConvertTo-Json -Depth 100 | Set-Content 'tmp.json'"

curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d @tmp.json
