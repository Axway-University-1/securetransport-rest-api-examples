@echo off
REM ==============================================================================
REM Script Name: 05.sites_id_HEAD.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script checks whether a transfer site exists, using the `/sites/{id}`
REM endpoint with HEAD: 200 when it does, 404 when it does not. The path takes the
REM site's id, so the script looks the id up by account and name first.
REM
REM Usage:
REM 05.sites_id_HEAD.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  the account the site belongs to (default john, or ST_EXAMPLE_ACCOUNT)
REM   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site is looked up by account and name, and must be the only one with that name.
REM - Confirmed directly: HEAD answers 200 for a site of any type and 404, with no body, for an
REM   id that does not exist. Two accounts may each have a site of the same name (201), but a
REM   second one in the same account is 409 "Entry already exist.". The `name=` filter
REM   ignores case and takes a * wildcard, so `example_x` and `EXAMPLE_X` (two different sites)
REM   both come back for either, and `example_x*` also finds `example_x2`: the script keeps only
REM   the exact name. The `account=` filter is exact, case sensitive, with no wildcard.
REM - PowerShell is used to read the id, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET NAME=%~2
IF "%NAME%"=="" SET NAME=SSH_PULL
SET LOOKUP_FILE=%TEMP%\site_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET SITE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SITE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% sites named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "%MAIN_URL%/%SITE_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" (
    echo The site %NAME% of %ACCOUNT% exists, id %SITE_ID%.
) ELSE (
    echo The site %NAME% of %ACCOUNT%, id %SITE_ID%, does not exist ^(HTTP %HTTP_CODE%^).
    EXIT /B 1
)
