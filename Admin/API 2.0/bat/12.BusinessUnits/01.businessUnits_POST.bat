@echo off
REM ==============================================================================
REM Script Name: 01.businessUnits_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a business unit using the `/businessUnits` endpoint.
REM
REM Usage:
REM 01.businessUnits_POST.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The baseFolder is the root under which the accounts of this business unit
REM   are created.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

echo Creating a Business Unit...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\":\"Finance\",\"baseFolder\":\"/home/fin\"}"
