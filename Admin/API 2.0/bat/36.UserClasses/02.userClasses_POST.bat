@echo off
REM ==============================================================================
REM Script Name: 02.userClasses_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a user class using the `/userClasses` endpoint.
REM It demonstrates:
REM - A class that matches one login name (the userName), with an optional membership expression
REM - That it is created disabled unless you say so, so that it cannot catch a login by accident
REM - Reading the new class's address from the Location header
REM
REM Usage:
REM 02.userClasses_POST.bat [NAME [USER_NAME [EXPRESSION [ENABLED [USER_TYPE]]]]]
REM
REM   NAME        the class's name, no spaces (default example_userclass)
REM   USER_NAME   the login names it matches; takes a * wildcard, is case sensitive (default example_nobody)
REM   EXPRESSION  a membership expression; none (default) leaves it out. Quote it
REM   ENABLED     true or false (default false)
REM   USER_TYPE   * (default, any), real or virtual
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A user class decides which class an account is in when it logs in. The server tries the classes in `order` and the
REM   FIRST enabled one that matches wins; a class matches when its userType, userName, group and address fit the login
REM   and its expression (when there is one) is true. The lab has two classes of its own, VirtClass (virtual) and RealClass
REM   (real), that match every login of their type: never change or delete them.
REM - Run 07.userClasses_id_DELETE.bat to remove what this creates. An enabled class with a wide USER_NAME takes the logins of
REM   every account it fits, and a new class is put FIRST, before VirtClass and RealClass: the script refuses an enabled class
REM   whose USER_NAME is *.
REM - Confirmed directly: a success is 201 with the new class's address in `Location` and no body. Required: `className`,
REM   `userType`, `userName`, `group` and `address` (the 400 lists each one missing). The reference's text says `host`, but the
REM   field is `address` (`host` is 400 "Unsupported parameter - host", as is any unknown field). `enabled` defaults to false and
REM   `expression` to the empty text; `order` in the body is IGNORED: the new class is put first (order 1) and the others move down
REM   one, VirtClass and RealClass too (they move back when it is deleted).
REM - Confirmed directly: a duplicate name is 409 "User class with this name already exists.", but names are case sensitive
REM   (`example_x` and `EXAMPLE_X` coexist). A blank name is 400 "className is empty.", a name with a space 400 "className contains
REM   whitespace."; dashes, dots and accents are accepted, and so is a name of 33 characters though the reference says 32. `userType`
REM   is exactly `*`, `real` or `virtual` (400 "Valid userType values are: *, real and virtual"). An empty userName, group or address
REM   is 400. `enabled` may be the text "true"; "abc" is 400.
REM - Confirmed directly: the expression is CHECKED when it is saved: 400 "expression X is not valid." for `1==1`, `user.name == "bob"`,
REM   `a && b`, `a || b`, `!a`, `gt`, `nonsense(` and a string method on a literal. It accepts `true`, `false`, `1 > 0`, `a and b`,
REM   `a or b`, `isset("A") ? x : y`, `memberof("CN=..",LDAP_DIR_memberOf$collection)` and a bare name or a method on one
REM   (`user.name.startsWith("a")`): the check is of the syntax, an unknown name is not refused. It is at most 1024 characters
REM   (400 "expression size must be between 0 and 1024").
REM - Confirmed directly, what it does: an SFTP, an EndUser API (HTTP) or an FTP login (same result over all three) of an account whose name fits is put in the class (the sessions list shows it
REM   as `userClass`: `GET /sessions?fields=userName,userClass`, see 32.Sessions), one that does not fit stays in VirtClass. `userName` is a pattern (`*_ab12`,
REM   `example_a*`), case sensitive; `userType` virtual fits a local account and real does not; `address` is the client's address, exact or
REM   with a `*` at the end (the first part of the address, then `.*`); a `group` that is not the account's, `enabled` false and an expression that is false do not match.
REM   The expression is true for `true`, `1 > 0`, `true or false`, and false for `false`, `2 > 3`, `not true` and any attribute test
REM   (`isset("LDAP_DIR_memberOf")`, `memberof(..)`): a local account has no directory attributes, and its additionalAttributes are not
REM   visible to an expression. Membership by an LDAP attribute was therefore NOT seen on the lab.
REM - PowerShell is used to build the request body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_userclass
SET USER_NAME=%~2
IF "%USER_NAME%"=="" SET USER_NAME=example_nobody
SET EXPRESSION=%~3
IF "%EXPRESSION%"=="" SET EXPRESSION=none
SET ENABLED=%~4
IF "%ENABLED%"=="" SET ENABLED=false
SET USER_TYPE=%~5
IF "%USER_TYPE%"=="" SET USER_TYPE=*
powershell -NoProfile -Command "if ($env:NAME.Trim() -eq '' -or $env:NAME -match '\s') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo NAME must not be empty or hold a space.
    EXIT /B 2
)
IF NOT "%ENABLED%"=="true" IF NOT "%ENABLED%"=="false" (
    echo ENABLED is true or false, not %ENABLED%.
    EXIT /B 2
)
IF NOT "%USER_TYPE%"=="*" IF NOT "%USER_TYPE%"=="real" IF NOT "%USER_TYPE%"=="virtual" (
    echo USER_TYPE is *, real or virtual, not %USER_TYPE%.
    EXIT /B 2
)
IF "%ENABLED%"=="true" IF "%USER_NAME%"=="*" (
    echo An enabled class for every user name would take the login of every account ^(a new class is tried first^). Refused.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:EXPRESSION.Length -gt 1024) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo EXPRESSION is 1024 characters at most.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\uclass_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\uclass_response_%RANDOM%.txt
SET HEADERS_FILE=%TEMP%\uclass_headers_%RANDOM%.txt

REM expression is left out when there is none
powershell -NoProfile -Command "$b = [ordered]@{ className = $env:NAME; userType = $env:USER_TYPE; userName = $env:USER_NAME; group = '*'; address = '*'; enabled = ($env:ENABLED -eq 'true') }; if ($env:EXPRESSION -ne 'none') { $b.expression = $env:EXPRESSION }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 6))"

echo Creating the user class %NAME% for the login names %USER_NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
