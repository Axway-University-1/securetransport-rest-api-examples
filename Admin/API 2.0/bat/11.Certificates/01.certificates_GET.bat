@echo off
REM ==============================================================================
REM Script Name: 01.certificates_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the certificates using the `/certificates` endpoint.
REM It demonstrates:
REM - Counting them, and listing a page
REM - Searching by usage (private, local, partner, login, trusted) and type
REM - The ones that expire within a number of days, with expirationTime.to
REM
REM Usage:
REM 01.certificates_GET.bat [USAGE [DAYS]]
REM
REM   USAGE  private, local, partner, login or trusted (default local); anything else is refused with exit 2, nothing sent
REM   DAYS   list the ones that expire within this many days (default 30)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: expirationTime.from and .to are in milliseconds since
REM   1970, though the API reference says a Unix timestamp. In seconds they find
REM   nothing.
REM - account= lists one account's certificates.
REM - PowerShell is used to print one certificate per line, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Confirmed directly: usage= takes those five words, in any case (LOCAL finds what local does), and a word it does not know
REM   (ca, signer, server) is not an empty list but 403 "Insufficient permissions to perform the operation", which says nothing
REM   of the usage. The script refuses such a word first.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when an argument is wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\certs_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET USAGE=%~1
IF "%USAGE%"=="" SET USAGE=local
SET DAYS=%~2
IF "%DAYS%"=="" SET DAYS=30
IF NOT "%~3"=="" GOTO usage
IF "%USAGE%"=="private" GOTO usage_ok
IF "%USAGE%"=="local" GOTO usage_ok
IF "%USAGE%"=="partner" GOTO usage_ok
IF "%USAGE%"=="login" GOTO usage_ok
IF "%USAGE%"=="trusted" GOTO usage_ok
echo USAGE is private, local, partner, login or trusted, not %USAGE%.
EXIT /B 2
:usage_ok
ECHO %DAYS%| FINDSTR /R /X "[0-9][0-9]*" >NUL || (
    echo DAYS must be a whole number: %DAYS%
    EXIT /B 2
)

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=id"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Certificates on the server: %%N

echo.
echo The x509 %USAGE% ones: name, subject, expires:
SET "URL=%MAIN_URL%?usage=%USAGE%&type=x509&fields=name,subject,expirationTime"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($c in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  {0}  {1}  {2}' -f $c.name, $c.subject, $c.expirationTime }"

REM Now and the limit, in milliseconds
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); '{0} {1}' -f $now, ($now + [int64]$env:DAYS * 86400000)"') DO (
    SET NOW=%%A
    SET UNTIL=%%B
)
echo.
echo The %USAGE% ones that expire within %DAYS% days:
SET "URL=%MAIN_URL%?usage=%USAGE%&expirationTime.from=%NOW%&expirationTime.to=%UNTIL%&fields=name,account,expirationTime"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($c in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { $a = $c.account; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}' -f $c.name, $a, $c.expirationTime }"
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
echo Usage: 01.certificates_GET.bat [USAGE [DAYS]]
EXIT /B 2
