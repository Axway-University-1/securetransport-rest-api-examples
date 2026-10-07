@echo off
REM ==============================================================================
REM Script Name: 02.daemons_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script queries the SSH daemon from the /daemons/{name} endpoint,
REM extracts the banner using PowerShell, checks if it's defined, and simulates
REM a fake banner check.
REM
REM Usage:
REM call 02_daemons_name_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - Requires curl and PowerShell.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

set NAME=ssh

REM Query the SSH daemon
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%"

REM Store response in a temporary file
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/%NAME%" -H "accept: application/json" -H "%REFERER_HEADER%" > daemon_response.txt

REM Extract banner using PowerShell
for /f "delims=" %%i in ('powershell -Command ^
    "$json = Get-Content -Raw 'daemon_response.txt' | ConvertFrom-Json; $json.banner"') do (
    set BANNER=%%i
)

REM Check if banner is defined
if "%BANNER%"=="" (
    echo There is no banner defined.
) else (
    echo There is a banner defined: '%BANNER%'.
)

REM Simulate a fake banner
set FAKE_JSON={"banner": "This is a SecureTransport REST API test banner."}
for /f "delims=" %%i in ('powershell -Command ^
    "$json = '%FAKE_JSON%' | ConvertFrom-Json; $json.banner"') do (
    set BANNER=%%i
)

REM Check if fake banner is defined
if "%BANNER%"=="" (
    echo There is no banner defined.
) else (
    echo There is a banner defined: '%BANNER%'.
)

REM Clean up
del daemon_response.txt >nul 2>&1
