@echo off
REM ==============================================================================
REM Script Name: 02.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates accounts using the `/accounts` endpoint.
REM It demonstrates creating one account of each type:
REM - user
REM - service
REM - template
REM
REM Usage:
REM 02.accounts_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A template account needs a user class. This example uses "VirtClass",
REM   but you can create your own and use it as the templateClass value.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

REM Simple POST to create an Account of type User
echo Creating an Account of type User...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\":\"UserAccount\",\"type\":\"user\",\"homeFolder\":\"/home/UserAccount\",\"uid\":\"1001\",\"gid\":\"1001\",\"user\":{\"name\":\"UserAccount\",\"passwordCredentials\":{\"password\":\"1\"}}}"

REM Simple POST to create an Account of type Service
echo Creating an Account of type Service...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\":\"ServiceAccount\",\"type\":\"service\",\"homeFolder\":\"/home/ServiceAccount\",\"uid\":\"1001\",\"gid\":\"1001\"}"

REM Simple POST to create an Account of type Template
echo Creating an Account of type Template...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{\"name\":\"TemplateAccount\",\"type\":\"template\",\"homeFolder\":\"/home/TemplateAccount\",\"uid\":\"1001\",\"gid\":\"1001\",\"templateClass\":\"VirtClass\"}"
