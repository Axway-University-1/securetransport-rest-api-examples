@echo off
REM ==============================================================================
REM Script Name: 02.accounts_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates accounts using the `/accounts` endpoint.
REM It demonstrates creating one account of each type, all of them harmless examples:
REM - user: example_user, with a password of your own (from the environment) or a generated one that is printed
REM - service: example_service
REM - template: example_template, in a user class that exists on the server (given, or looked up)
REM
REM Usage:
REM [SET ACCOUNT_PASSWORD=the password of example_user]
REM 02.accounts_POST.bat [TEMPLATE_CLASS]
REM
REM   ACCOUNT_PASSWORD  the password of example_user, from the environment (optional): when it is not set, one is generated and printed
REM   TEMPLATE_CLASS    the user class of the template account (default: the first class of the server whose type is not real,
REM                     looked up with GET /userClasses; VirtClass is never assumed)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The three accounts are example_user, example_service and example_template, so running this bare changes nothing that matters. 07.accounts_name_DELETE.bat removes them.
REM   The other scripts of this folder act on example_user by default.
REM - A template account needs a user class (`templateClass`). It is taken from the first argument, or looked up: the classes of the server are read first and the first one of type
REM   `virtual` (or `*`) is used, by its `order`. If there is none, the script says so and sends nothing (exit 1). Confirmed directly: a class that does not exist is accepted by the
REM   server all the same (see 36.UserClasses), so a given class is not checked.
REM - The password is never in the file. A generated one (12 random letters and digits after a fixed beginning that satisfies a password policy) is printed once.
REM - The uid and gid are fixed at 41733 on purpose: a home folder outlives its account and keeps the uid it was created with, so a later account of the same name
REM   with another uid could not create a folder in it (a 403, see st-api-gotchas, "A home folder outlives its account").
REM - PowerShell is used to look the class up and build each body, in place of jq.
REM - Confirmed directly: each creation answers 201 with no body and the new account's address in `Location`; a second one with the same name is 409
REM   "Unable to create account 'example_user': The account name is not unique." A user account created this way has the address book sources LDAP and Local already.
REM - Exit codes: 0 when all three were created (201), 1 when the server refuses one (the others are still tried) or no user class can be found, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET USER_NAME=example_user
SET SERVICE_NAME=example_service
SET TEMPLATE_NAME=example_template
SET USAGE=Usage: [SET ACCOUNT_PASSWORD=the password of example_user ^&] 02.accounts_POST.bat [TEMPLATE_CLASS]
SET TEMPLATE_CLASS=%~1
IF NOT "%~2"=="" (
    echo %USAGE%
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\account_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\account_body_%RANDOM%.json

SET GENERATED=
IF NOT DEFINED ACCOUNT_PASSWORD (
    REM A generated password: written to a file by PowerShell and read back (a FOR /F command cannot hold single quotes)
    powershell -NoProfile -Command "[IO.File]::WriteAllText($env:RESPONSE_FILE, 'Ex1!' + (-join ((48..57) + (65..90) + (97..122) | Get-Random -Count 12 | ForEach-Object { [char]$_ })))"
    SET /P ACCOUNT_PASSWORD=<"%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    SET GENERATED=yes
)

IF "%TEMPLATE_CLASS%"=="" CALL :find_class
IF "%TEMPLATE_CLASS%"=="" (
    echo Could not find a user class for the template account. Nothing was created: give one as the first argument.
    EXIT /B 1
)
IF "%~1"=="" echo Using the user class %TEMPLATE_CLASS%.

SET FAILED=0

REM Simple POST to create an Account of each type
CALL :create_account user %USER_NAME% "an Account of type User"
CALL :create_account service %SERVICE_NAME% "an Account of type Service"
CALL :create_account template %TEMPLATE_NAME% "an Account of type Template"

IF "%GENERATED%"=="yes" echo The password of %USER_NAME% is %ACCOUNT_PASSWORD% ^(generated: it is not shown again^).
EXIT /B %FAILED%

REM ------------------------------------------------------------------------------
REM Looks up a user class for the template account: the first one, by order, whose type is not real
REM ------------------------------------------------------------------------------
:find_class
echo Looking up a user class for the template account...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses" --data-urlencode "fields=className,userType,order" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" GOTO class_done
SET CLASS_FILE=%TEMP%\account_class_%RANDOM%.txt
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $c = @($r.result | Where-Object { $_.userType -ne 'real' } | Sort-Object { [int]$_.order }); $name = ''; if ($c.Count -gt 0) { $name = [string]$c[0].className }; [IO.File]::WriteAllText($env:CLASS_FILE, $name)"
SET /P TEMPLATE_CLASS=<"%CLASS_FILE%"
IF EXIST "%CLASS_FILE%" DEL "%CLASS_FILE%"
:class_done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Creates the account of type %1 named %2; %3 is what to call it in the message
REM ------------------------------------------------------------------------------
:create_account
SET ACCOUNT_TYPE=%~1
SET ACCOUNT_NAME=%~2
powershell -NoProfile -Command "$n = $env:ACCOUNT_NAME; $b = [ordered]@{ name = $n; type = $env:ACCOUNT_TYPE; homeFolder = '/home/' + $n; uid = '41733'; gid = '41733' }; if ($env:ACCOUNT_TYPE -eq 'user') { $b.user = [ordered]@{ name = $n; passwordCredentials = [ordered]@{ password = $env:ACCOUNT_PASSWORD } } }; if ($env:ACCOUNT_TYPE -eq 'template') { $b.templateClass = $env:TEMPLATE_CLASS }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 10))"
echo Creating %~3 (%ACCOUNT_NAME%)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    SET FAILED=1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
