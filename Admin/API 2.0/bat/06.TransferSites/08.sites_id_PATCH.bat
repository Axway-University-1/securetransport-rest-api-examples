@echo off
REM ==============================================================================
REM Script Name: 08.sites_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a transfer site, using the `/sites/{id}`
REM endpoint with PATCH: a JSON Patch document that replaces the download folder.
REM Unlike PUT (07.sites_id_PUT.bat), it sends only what changes.
REM
REM Usage:
REM 08.sites_id_PATCH.bat ACCOUNT NAME [FOLDER]
REM
REM   ACCOUNT  the account the site belongs to
REM   NAME     the site (it must be the only one with that name)
REM   FOLDER   the new download folder (default /inbox)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the folder before, to put it back with.
REM - Only a site with a download folder (SSH, FTP, HTTP, folder monitor) can be patched this
REM   way; the script says so for the others (a PeSIT or AS2 site has no such field).
REM - Confirmed directly: a success answers 204, with no body. `replace` works on a field that
REM   is null; `add` creates a nested one (`/postTransmissionActions/doAsOut`) and `remove`
REM   sets it back to null, not absent. An empty patch is 204. `add` to `/additionalAttributes/
REM   userVars.<name>` works. `type` is read only (400 "Patch operation on read only or
REM   discriminator fields is not permitted."), a path that does not exist is 400 `Missing
REM   field "nosuch"`, a wrong value type 400 "Something went wrong while patching the entity.",
REM   and a failing `test` operation is 400. `replace` of `/id` and of `/account` answer 204 and
REM   change nothing; of `/name` it renames the site.
REM - PowerShell is used to read the id and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
SET NAME=%~2
IF "%ACCOUNT%"=="" GOTO :usage
IF "%NAME%"=="" GOTO :usage
SET FOLDER=%~3
IF "%FOLDER%"=="" SET FOLDER=/inbox
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
SET FIELD_NAME=downloadFolder
SET NONE_TEXT=(none)
SET NOFIELD_TEXT=@@no-such-field@@
SET BEFORE=
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$s = Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json; if ($s.PSObject.Properties.Name -contains $env:FIELD_NAME) { if ($s.downloadFolder) { $s.downloadFolder } else { $env:NONE_TEXT } } else { $env:NOFIELD_TEXT }"') DO SET BEFORE=%%D
IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"
IF "%BEFORE%"=="%NOFIELD_TEXT%" (
    echo The site %NAME% has no download folder to change.
    EXIT /B 1
)
echo The download folder of %NAME% is now %BEFORE%.
SET BODY_FILE=%TEMP%\site_patch_%RANDOM%.json
powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/downloadFolder'; value = $env:FOLDER }; ConvertTo-Json -InputObject @($op) -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %FOLDER%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%SITE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
EXIT /B 0

:usage
echo Usage: 08.sites_id_PATCH.bat ACCOUNT NAME [FOLDER]
EXIT /B 2
