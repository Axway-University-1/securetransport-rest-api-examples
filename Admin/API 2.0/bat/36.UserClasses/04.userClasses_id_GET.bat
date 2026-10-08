@echo off
REM ==============================================================================
REM Script Name: 04.userClasses_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves one user class, using the `/userClasses/{id}` endpoint.
REM The path takes the class's id, so the script looks the id up by name first.
REM It prints a short summary of the class, then only some fields of it.
REM
REM Usage:
REM 04.userClasses_id_GET.bat [NAME]
REM
REM   NAME  the class (default example_userclass)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The class is looked up by name, and must be the only one with that name.
REM - Confirmed directly: the object has `id`, `className`, `userType`, `userName`, `group`, `address`, `expression` (the empty text
REM   when none), `enabled` and `order`, and no `metadata`. An unknown id, well formed or not, is a JSON 404 "User Class with ID \"X\"
REM   does not exist."; `fields=` keeps the keys named and an unknown field is 400.
REM - PowerShell is used to read the id and print the summary, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\uclass_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_userclass
IF NOT "%~2"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "className=%NAME%" --data-urlencode "fields=id,className"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET CLASS_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.className -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CLASS_ID=%%B
)
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% user classes named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

echo The user class %NAME%, id %CLASS_ID%:

SET "URL=%MAIN_URL%/%CLASS_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the user class %NAME% ^(id %CLASS_ID%^).
    EXIT /B 1
)
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $e = if ($j.expression) { $j.expression } else { '-' }; '  order:      {0}' -f $j.order; '  type:       {0}' -f $j.userType; '  user name:  {0}' -f $j.userName; '  group:      {0}' -f $j.group; '  address:    {0}' -f $j.address; '  enabled:    {0}' -f ([string]$j.enabled).ToLower(); '  expression: {0}' -f $e"

echo.
echo Only some fields of it:
SET "URL=%MAIN_URL%/%CLASS_ID%"
SET CURL_OPTS=-G --data-urlencode "fields=className,enabled"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
TYPE "%RESPONSE_FILE%"
echo.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 04.userClasses_id_GET.bat [NAME]
EXIT /B 2
