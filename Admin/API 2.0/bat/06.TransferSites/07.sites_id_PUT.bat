@echo off
REM ==============================================================================
REM Script Name: 07.sites_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a transfer site, using the `/sites/{id}` endpoint with PUT: it
REM reads the site, changes how many connections it may open at once
REM (maxConcurrentConnection, which every type of site has), and sends the whole site
REM back.
REM
REM Usage:
REM 07.sites_id_PUT.bat ACCOUNT NAME [VALUE]
REM
REM   ACCOUNT  the account the site belongs to
REM   NAME     the site (it must be the only one with that name)
REM   VALUE    the new maxConcurrentConnection, 0 to 65535 (default 2; 0 means no limit)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put it back with.
REM - PUT replaces the whole site. Confirmed directly: a hand-built fragment (the name, host,
REM   port, user and password only) answers 204 and silently resets everything left out, the
REM   folders, the pattern, the renaming and the connection limit. That is why the site is read
REM   first and sent back with only one field changed. metadata, the read-only links, is left out.
REM - Confirmed directly: a success answers 204, with no body. The site read back carries the
REM   password encrypted, and sending that text back keeps the password; a body with no password
REM   is 400 "Specify password", and plain text is encrypted anew. An unknown id is a JSON 404.
REM   A body with another `name` renames the site; one with another `account` is accepted (204)
REM   and ignored; a different `type` is refused, 400, and so is a body with no `type`.
REM - PowerShell is used to read the id and edit the site, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
SET NAME=%~2
IF "%ACCOUNT%"=="" GOTO :usage
IF "%NAME%"=="" GOTO :usage
SET VALUE=%~3
IF "%VALUE%"=="" SET VALUE=2
powershell -NoProfile -Command "if ($env:VALUE -match '^[0-9]+$' -and [int]$env:VALUE -le 65535) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo VALUE is a number from 0 to 65535, not %VALUE%.
    EXIT /B 2
)
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
SET SITE_FILE=%TEMP%\site_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SITE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SITE_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the site %NAME% ^(id %SITE_ID%^).
    IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json).maxConcurrentConnection"') DO echo maxConcurrentConnection of %NAME% is now %%D.
powershell -NoProfile -Command "$s = Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json; $s.maxConcurrentConnection = [int]$env:VALUE; $s.PSObject.Properties.Remove('metadata'); $s | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%SITE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 07.sites_id_PUT.bat ACCOUNT NAME [VALUE]
EXIT /B 2
