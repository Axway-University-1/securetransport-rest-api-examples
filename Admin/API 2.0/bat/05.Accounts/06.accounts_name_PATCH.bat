@echo off
REM ==============================================================================
REM Script Name: 06.accounts_name_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs partial updates to an account using the
REM `/accounts/{name}` endpoint with the PATCH method.
REM
REM The PATCH method has three types of operations: add, remove, and replace.
REM It demonstrates:
REM - Replacing a single field
REM - Replacing two fields in one request
REM - Removing a field
REM - Adding an element to an array
REM
REM Usage:
REM 06.accounts_name_PATCH.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The add operation is best suited for arrays. You can use it to add a new
REM   element to an empty or non-empty array.
REM - The path "/addressBookSettings/policy" means that there is a first level
REM   property named "addressBookSettings" with a property named "policy" under it.
REM - From the schema, the policy can be "default", "custom" or "disabled".
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts

echo Getting the account %ACCOUNT% and filtering only the addressBookSettings...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%?type=user&fields=addressBookSettings.policy,addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "%REFERER_HEADER%"

echo Changing the policy to custom...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{ \"op\": \"replace\", \"path\": \"/addressBookSettings/policy\", \"value\": \"custom\" }]"

REM Now let's repeat the query, but this time modify two parameters at once
echo Changing two fields at the same time...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{ \"op\": \"replace\", \"path\": \"/addressBookSettings/policy\", \"value\": \"default\" }, { \"op\": \"replace\", \"path\": \"/addressBookSettings/nonAddressBookCollaborationAllowed\", \"value\": \"true\" }]"

echo Removing the addressBookSettings.nonAddressBookCollaborationAllowed...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{ \"op\": \"remove\", \"path\": \"/addressBookSettings/nonAddressBookCollaborationAllowed\" }]"

echo Checking the result...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ACCOUNT%?type=user&fields=addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "%REFERER_HEADER%"

echo Adding a new contact...
REM "-" appends to the end of the array whether it is empty or not - a numeric
REM index like "1" only works if the array already has an element at index 0,
REM confirmed against a real server: it 400s with "Array index 1 out of
REM bounds" on a freshly created account with no contacts yet.
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%ACCOUNT%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "[{ \"op\": \"add\", \"path\": \"/addressBookSettings/contacts/-\", \"value\": { \"fullName\": \"Jane Doe\", \"primaryEmail\": \"jane.doe@abc.com\" } }]"
