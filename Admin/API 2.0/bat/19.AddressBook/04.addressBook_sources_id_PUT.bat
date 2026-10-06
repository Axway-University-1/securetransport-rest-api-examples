@echo off
REM ==============================================================================
REM Script Name: 04.addressBook_sources_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces an address book source, using the
REM `/addressBook/sources/{id}` endpoint with PUT: it reads the source, changes
REM the number of entries a page of the address book shows (MaxPageEntries), and
REM sends the whole source back.
REM
REM Usage:
REM 04.addressBook_sources_id_PUT.bat MAX_PAGE_ENTRIES [SOURCE]
REM
REM   MAX_PAGE_ENTRIES  the new page size
REM   SOURCE            the source's name (default LDAP)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before the change, to put it back with.
REM - A source is a server-wide setting that every end user's address book
REM   reads: change it with care.
REM - Confirmed directly: a success answers 204, with no body.
REM - 05.addressBook_sources_id_PATCH.bat changes the same field with PATCH.
REM - PowerShell is used to read and edit the source, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/addressBook/sources

SET MAX_PAGE_ENTRIES=%~1
SET SOURCE=%~2
IF "%SOURCE%"=="" SET SOURCE=LDAP
ECHO %MAX_PAGE_ENTRIES%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo Usage: 04.addressBook_sources_id_PUT.bat MAX_PAGE_ENTRIES [SOURCE]
    EXIT /B 2
)
SET SOURCE_FILE=%TEMP%\source_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "name=%SOURCE%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SOURCE_FILE%"
SET SOURCE_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SOURCE_FILE | ConvertFrom-Json).result[0].id } catch { }"') DO SET SOURCE_ID=%%I
IF "%SOURCE_ID%"=="" (
    echo There is no address book source named %SOURCE%.
    IF EXIST "%SOURCE_FILE%" DEL "%SOURCE_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\source_body_%RANDOM%.json
FOR /F "delims=" %%V IN ('powershell -NoProfile -Command "$s = (Get-Content -Raw $env:SOURCE_FILE | ConvertFrom-Json).result[0]; if ($s.customProperties.MaxPageEntries) { $s.customProperties.MaxPageEntries } else { 'not set' }"') DO echo MaxPageEntries of %SOURCE% is now %%V.

REM The whole source, with the one property changed. Custom properties are strings.
powershell -NoProfile -Command "$s = (Get-Content -Raw $env:SOURCE_FILE | ConvertFrom-Json).result[0]; $s.customProperties | Add-Member -Force -NotePropertyName MaxPageEntries -NotePropertyValue ([string]$env:MAX_PAGE_ENTRIES); $s | ConvertTo-Json -Depth 10 -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"
echo Setting it to %MAX_PAGE_ENTRIES%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%SOURCE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%SOURCE_FILE%" DEL "%SOURCE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" EXIT /B 1
