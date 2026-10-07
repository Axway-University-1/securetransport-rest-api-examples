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
REM   USAGE  private, local, partner, login or trusted (default local)
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
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET USAGE=%~1
IF "%USAGE%"=="" SET USAGE=local
SET DAYS=%~2
IF "%DAYS%"=="" SET DAYS=30
ECHO %DAYS%| FINDSTR /R /X "[0-9][0-9]*" >NUL || (
    echo DAYS must be a whole number: %DAYS%
    EXIT /B 2
)
SET RESPONSE_FILE=%TEMP%\certs_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Certificates on the server: %%N

echo.
echo The x509 %USAGE% ones: name, subject, expires:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?usage=%USAGE%&type=x509&fields=name,subject,expirationTime" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($c in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { '  {0}  {1}  {2}' -f $c.name, $c.subject, $c.expirationTime }"

REM Now and the limit, in milliseconds
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); '{0} {1}' -f $now, ($now + [int64]$env:DAYS * 86400000)"') DO (
    SET NOW=%%A
    SET UNTIL=%%B
)
echo.
echo The %USAGE% ones that expire within %DAYS% days:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET ^
  "%MAIN_URL%?usage=%USAGE%&expirationTime.from=%NOW%&expirationTime.to=%UNTIL%&fields=name,account,expirationTime" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($c in (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result) { $a = $c.account; if (-not $a) { $a = '-' }; '  {0}  {1}  {2}' -f $c.name, $a, $c.expirationTime }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
