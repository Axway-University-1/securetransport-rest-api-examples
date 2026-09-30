@echo off
REM ==============================================================================
REM Script Name: 04.daemons_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This batch script sends PATCH requests to update specific fields of the SSH
REM daemon using the /daemons/{name} endpoint. It demonstrates how to patch
REM individual attributes such as maxConnections, preferBouncyCastleProvider,
REM and banner.
REM
REM Usage:
REM call 04_daemons_name_PATCH.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is called beforehand to set required variables.
REM - Requires curl and PowerShell.
REM ==============================================================================

echo Loading variables into our context...
call ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

set NAME=ssh

echo.
echo Patching the daemon maxConnections...
curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/%NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "[{ \"op\": \"replace\", \"path\": \"/maxConnections\", \"value\": 4 }]"

echo.
echo Patching the daemon preferBouncyCastleProvider...
curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/%NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "[{ \"op\": \"replace\", \"path\": \"/preferBouncyCastleProvider\", \"value\": true }]"

echo.
echo Patching the daemon banner...
curl -s -o nul -w "%%{http_code}\n" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/%NAME%" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -d "[{ \"op\": \"replace\", \"path\": \"/banner\", \"value\": \"New banner\" }]"
