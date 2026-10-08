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
REM 06.accounts_name_PATCH.bat [NAME]
REM
REM   NAME  the user account (default example_user, the one 02.accounts_POST.bat creates)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The add operation is best suited for arrays. You can use it to add a new
REM   element to an empty or non-empty array.
REM - The path "/addressBookSettings/policy" means that there is a first level
REM   property named "addressBookSettings" with a property named "policy" under it.
REM - From the schema, the policy can be "default", "custom" or "disabled".
REM - It changes the address book settings of the account and leaves a contact in them. It first reads and prints the old settings, then the body that puts the policy and the flag
REM   back, and afterwards the one that takes the contact out again. Deleting the account (07.accounts_name_DELETE.bat) removes all of it.
REM - The change to "custom" is only tried when the account has at least two address book sources; it is refused otherwise (400 "addressBookSettings.sources must be at least two."),
REM   and the script says it skips it. The accounts this lab creates have the two (LDAP and Local), and a plain 204 follows.
REM - PowerShell is used to read the settings and build each patch, in place of jq.
REM - "-" appends to the end of an array, empty or not; a numeric index like "1" only works when index 0 is taken (400 "Array index 1 out of bounds").
REM - Confirmed directly: each PATCH answers 204 with no body. `remove` of `nonAddressBookCollaborationAllowed` answers 204 and the field reads back null (it stays in the object).
REM   The value "true" and the boolean true are both accepted and read back as true. A path that does not exist is 400 `Missing field "nope"`, and on a service account the
REM   address book settings do not exist (400 `Missing field "addressBookSettings"`).
REM - Exit codes: 0 when every call answered as expected, 1 when the account cannot be read or the server refuses a patch (the later ones are not sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET ACCOUNT_URL=%MAIN_URL%/%NAME_URI%
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\account_body_%RANDOM%.json

REM The PATCH Method has 3 types of operations: add, remove, and replace.
REM
REM OPERATION = ADD
REM The add operation is best suited for arrays. You can use it to add a new element to an empty or non-empty array.
REM
REM We will use the replace operation on policy. From the schema we can see that the policy can be
REM "default", "custom" or "disabled". We will change the policy to "custom".

echo Getting the account %NAME% and filtering only the addressBookSettings...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%ACCOUNT_URL%" --data-urlencode "type=user" --data-urlencode "fields=addressBookSettings" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
SET SOURCES=0
SET CONTACTS=0
REM How many sources and contacts there are: written to a file by PowerShell and read back (a FOR /F command cannot hold single quotes)
SET COUNTS_FILE=%TEMP%\account_counts_%RANDOM%.txt
powershell -NoProfile -Command "$s = (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).addressBookSettings; [IO.File]::WriteAllText($env:COUNTS_FILE, ('{0} {1}' -f @($s.sources | Where-Object { $_ -ne $null }).Count, @($s.contacts | Where-Object { $_ -ne $null }).Count))"
SET /P COUNTS=<"%COUNTS_FILE%"
IF EXIST "%COUNTS_FILE%" DEL "%COUNTS_FILE%"
FOR /F "tokens=1,2" %%A IN ("%COUNTS%") DO (
    SET SOURCES=%%A
    SET CONTACTS=%%B
)
powershell -NoProfile -Command "$s = (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).addressBookSettings; $flag = if ($null -eq $s.nonAddressBookCollaborationAllowed) { 'null' } else { ([string]$s.nonAddressBookCollaborationAllowed).ToLower() }; 'The address book settings of {0} are now: policy {1}, nonAddressBookCollaborationAllowed {2}, {3} sources, {4} contacts.' -f $env:NAME, $s.policy, $flag, @($s.sources | Where-Object { $_ -ne $null }).Count, @($s.contacts | Where-Object { $_ -ne $null }).Count; $ops = @([ordered]@{ op = 'replace'; path = '/addressBookSettings/policy'; value = $s.policy }); if ($null -eq $s.nonAddressBookCollaborationAllowed) { $ops += [ordered]@{ op = 'remove'; path = '/addressBookSettings/nonAddressBookCollaborationAllowed' } } else { $ops += [ordered]@{ op = 'replace'; path = '/addressBookSettings/nonAddressBookCollaborationAllowed'; value = $s.nonAddressBookCollaborationAllowed } }; 'To put the policy and the flag back, PATCH this body: ' + (ConvertTo-Json -InputObject $ops -Compress)"

IF %SOURCES% GEQ 2 (
    powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/addressBookSettings/policy'; value = 'custom' }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"
    CALL :patch "Changing the policy to custom"
    IF ERRORLEVEL 1 EXIT /B 1
) ELSE (
    echo Skipping the change to custom: it needs at least two address book sources and this account has %SOURCES%.
)

REM Now let's repeat the query, but this time modify two parameters at once
powershell -NoProfile -Command "$ops = @([ordered]@{ op = 'replace'; path = '/addressBookSettings/policy'; value = 'default' }, [ordered]@{ op = 'replace'; path = '/addressBookSettings/nonAddressBookCollaborationAllowed'; value = 'true' }); [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject $ops -Compress))"
CALL :patch "Changing two fields at the same time"
IF ERRORLEVEL 1 EXIT /B 1

powershell -NoProfile -Command "$op = [ordered]@{ op = 'remove'; path = '/addressBookSettings/nonAddressBookCollaborationAllowed' }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"
CALL :patch "Removing the addressBookSettings.nonAddressBookCollaborationAllowed"
IF ERRORLEVEL 1 EXIT /B 1

echo Checking the result...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%ACCOUNT_URL%" --data-urlencode "type=user" --data-urlencode "fields=addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "%REFERER_HEADER%"
echo.

REM "-" appends to the end of the array whether it is empty or not - a numeric
REM index like "1" only works if the array already has an element at index 0,
REM confirmed against a real server: it 400s with "Array index 1 out of
REM bounds" on a freshly created account with no contacts yet.
powershell -NoProfile -Command "$op = [ordered]@{ op = 'add'; path = '/addressBookSettings/contacts/-'; value = [ordered]@{ fullName = 'Jane Doe'; primaryEmail = 'jane.doe@abc.com' } }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress -Depth 5))"
CALL :patch "Adding a new contact"
IF ERRORLEVEL 1 EXIT /B 1
echo To take the contact out again, PATCH this body: [{"op":"remove","path":"/addressBookSettings/contacts/%CONTACTS%"}]
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Sends the patch in BODY_FILE and says %~1; exit 1 when the server does not answer 204
REM ------------------------------------------------------------------------------
:patch
echo %~1...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%ACCOUNT_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="204" EXIT /B 0
CALL :show_error
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 1

:show_error
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
