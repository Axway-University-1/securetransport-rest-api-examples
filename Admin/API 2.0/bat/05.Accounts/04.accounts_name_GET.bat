@echo off
REM ==============================================================================
REM Script Name: 04.accounts_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves a single account using the `/accounts/{name}` endpoint.
REM It demonstrates:
REM - Retrieving the whole object
REM - Selecting individual fields
REM - Why the type is needed for fields that are specific to one account type
REM
REM Usage:
REM 04.accounts_name_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The type is always returned, even when it is not listed in the fields.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=UserAccount
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

REM Simple GET to retrieve everything about a specific account
echo GET /api/v2.0/accounts/%ACCOUNT%
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%"

REM GET only the name, uid, and gid
REM Pay attention that the type is also returned no matter that it is not specified in the fields
echo GET /api/v2.0/accounts/%ACCOUNT%?fields=name,uid,gid
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%?fields=name,uid,gid" -H "accept: */*" -H "%REFERER_HEADER%"

REM If we want to receive fields that are not common to all account types, but are
REM specific to the user one, we have to specify the type.
REM Let's try with the addressBookSettings and without the type.
echo GET /api/v2.0/accounts/%ACCOUNT%?fields=addressBookSettings
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%?fields=addressBookSettings" -H "accept: */*" -H "%REFERER_HEADER%"

REM And now by specifying the type=user
echo GET /api/v2.0/accounts/%ACCOUNT%?type=user^&fields=addressBookSettings
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%?type=user&fields=addressBookSettings" -H "accept: */*" -H "%REFERER_HEADER%"
