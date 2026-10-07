@echo off
REM ==============================================================================
REM Script Name: 06.certificates_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes a certificate, using the `/certificates/{id}` endpoint
REM with PATCH: it makes the certificate visible to every administrator
REM (accessLevel PUBLIC) and tags it with an additional attribute.
REM
REM Usage:
REM 06.certificates_id_PATCH.bat [NAME [ACCESS_LEVEL]]
REM
REM   NAME          the certificate's name (default example_cert)
REM   ACCESS_LEVEL  PRIVATE, PUBLIC or BUSINESS_UNIT (default PUBLIC)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The certificate is looked up by name, and must be the only one with that name.
REM - Confirmed directly: PATCH works on accessLevel, additionalAttributes and
REM   the external store fields only. Anything else answers 400 with that list.
REM   A certificate's content cannot change: generate or import a new one.
REM - Confirmed directly: a success answers 204, with no body.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/certificates
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_cert
SET ACCESS_LEVEL=%~2
IF "%ACCESS_LEVEL%"=="" SET ACCESS_LEVEL=PUBLIC
IF NOT "%ACCESS_LEVEL%"=="PRIVATE" IF NOT "%ACCESS_LEVEL%"=="PUBLIC" IF NOT "%ACCESS_LEVEL%"=="BUSINESS_UNIT" (
    echo ACCESS_LEVEL is PRIVATE, PUBLIC or BUSINESS_UNIT, not %ACCESS_LEVEL%.
    EXIT /B 2
)
SET LOOKUP_FILE=%TEMP%\cert_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET CERT_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result); if ($r.Count -eq 1) { '1 ' + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CERT_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% certificates named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

echo Setting accessLevel of %NAME% to %ACCESS_LEVEL%, and tagging it...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%CERT_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "[{\"op\":\"replace\",\"path\":\"/accessLevel\",\"value\":\"%ACCESS_LEVEL%\"},{\"op\":\"add\",\"path\":\"/additionalAttributes/userVars.owner\",\"value\":\"example\"}]"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
