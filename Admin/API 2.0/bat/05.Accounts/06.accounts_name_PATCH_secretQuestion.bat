@echo off
REM ==============================================================================
REM Script Name: 06.accounts_name_PATCH_secretQuestion.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-21
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script makes an end user choose a new secret question, using the `/accounts/{name}` endpoint with PATCH.
REM It sets `forceSecretQuestionChange` of the account's secret question. While it is set, the user's own call
REM GET /myself/secretQuestion answers `error.secretQuestion.required` ("You have to set a new secret question")
REM until they set one with PUT /myself/secretQuestion: the nearest an administrator gets to taking a question away.
REM
REM Usage:
REM 06.accounts_name_PATCH_secretQuestion.bat [NAME [true|false]]
REM
REM   NAME   the user account (default example_user, the one 02.accounts_POST.bat creates)
REM   true|false  force the change (default true), or take the requirement away again
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Nothing clears a secret question. Confirmed directly (5.5-20260924): the end user's DELETE of /myself/secretQuestion is 405,
REM   and a PUT with an empty or null question or answer is 400. Here the administrator's PATCH `remove` of /user/secretQuestion, a `replace`
REM   of it or of its secretQuestion with null, and a PUT of the whole account without it all answer 204 and change nothing: the question reads back as it was.
REM   The only field that takes is forceSecretQuestionChange, which this script sets. A full PUT of the account resets it to false.
REM - While it is set the account's login and nearly every call answer 403 error.secretQuestion.required (confirmed): only GET /secretQuestions and the
REM   PUT /myself/secretQuestion that sets the new question are answered, with Basic authentication. That PUT lifts it; so does running this again with false.
REM - The service must be on (the server option Users.SecretQuestion.Enabled); the question the user then chooses has to be on the list (GET /secretQuestions).
REM - The answer is never returned by any call. secretAnswerGuessFailures counts the wrong guesses at it.
REM - It reads the account first and says what it found. An account that has no secret question, or that is not a user account (a service account has no `user` object), is left alone (exit 0).
REM - PowerShell is used to read the account and build the patch, in place of jq.
REM - Exit codes: 0 when the flag is set as asked (or there is no question), 1 when the account cannot be read or the server refuses the patch, 2 when the second argument is not true or false.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accounts
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_user
SET FORCE=%~2
IF "%FORCE%"=="" SET FORCE=true
IF NOT "%FORCE%"=="true" IF NOT "%FORCE%"=="false" (
    echo Usage: 06.accounts_name_PATCH_secretQuestion.bat [NAME [true^|false]]
    EXIT /B 2
)
SET NAME_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET NAME_URI=%%E
SET ACCOUNT_URL=%MAIN_URL%/%NAME_URI%
SET RESPONSE_FILE=%TEMP%\account_sq_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\account_sq_body_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B %RC%

:main
CALL :read_question
IF ERRORLEVEL 1 EXIT /B 1
IF "%QUESTION%"=="" (
    echo %NAME% has no secret question ^(or is not a user account^): nothing to force.
    EXIT /B 0
)
echo The secret question of %NAME% now: %QUESTION%

echo Setting forceSecretQuestionChange to %FORCE%...
powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/user/secretQuestion/forceSecretQuestionChange'; value = ($env:FORCE -eq 'true') }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%ACCOUNT_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    EXIT /B 1
)

CALL :read_question
IF ERRORLEVEL 1 EXIT /B 1
echo Read back: %QUESTION%
SET FLAG=
FOR /F "delims=" %%F IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).user.secretQuestion.forceSecretQuestionChange.ToString().ToLower()"') DO SET FLAG=%%F
IF NOT "%FLAG%"=="%FORCE%" (
    echo The flag did not take.
    EXIT /B 1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM The secret question object of the account, in QUESTION (empty when there is none). The answer of the call is kept in RESPONSE_FILE.
REM ------------------------------------------------------------------------------
:read_question
SET HTTP_CODE=
SET QUESTION=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%ACCOUNT_URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the account %NAME%: HTTP %HTTP_CODE%
    CALL :show_error
    EXIT /B 1
)
FOR /F "delims=" %%Q IN ('powershell -NoProfile -Command "$q = (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).user.secretQuestion; if ($q) { ConvertTo-Json -InputObject $q -Compress }"') DO SET QUESTION=%%Q
EXIT /B 0

:show_error
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
