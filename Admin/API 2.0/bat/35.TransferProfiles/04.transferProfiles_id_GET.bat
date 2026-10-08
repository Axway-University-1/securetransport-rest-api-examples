@echo off
REM ==============================================================================
REM Script Name: 04.transferProfiles_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves one transfer profile, using the `/transferProfiles/{id}` endpoint.
REM The path takes the profile's id, so the script looks the id up by account and name first.
REM It prints a short summary of the profile (with the advanced settings, when they are on), then only some fields of it.
REM
REM Usage:
REM 04.transferProfiles_id_GET.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  the account the profile belongs to (default john)
REM   NAME     the profile (default TP)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The profile is looked up by account and name, and must be the only one with that name.
REM - Confirmed directly: an unknown id, well formed or not, is a JSON 404 "Transfer Profile with id X not found or not
REM   accessible."; `fields=` keeps the keys named (`fields=name,sendMapping`) and an unknown field is 400. The profile
REM   carries `advancedSettings` (transcoding of what is sent and of what is received, and `receiverMessage`) with every
REM   default filled in; `enabled` false means the top level `transferMode`, `recordFormat`, `recordLength` and
REM   `paddingStripEnabled` are the ones in force, and `enabled` true that the advanced `type`s of the two sides are (check 59). `metadata.links.account` is the only link.
REM - PowerShell is used to read the id and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=TP
SET LOOKUP_FILE=%TEMP%\tprof_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET PROFILE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET PROFILE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% transfer profiles named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)

echo The transfer profile %NAME% of %ACCOUNT%, id %PROFILE_ID%:
SET PROFILE_FILE=%TEMP%\tprof_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%PROFILE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%PROFILE_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the transfer profile %NAME% ^(id %PROFILE_ID%^).
    IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$j = Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json; '  default:     {0}' -f ([string]$j.default).ToLower(); '  send:        {0}' -f $j.sendMapping; '  receive:     {0}' -f $j.receiveMapping; '  file label:  {0}' -f $j.fileLabelOption; '  mode:        {0}, {1} records of {2}' -f $j.transferMode, $j.recordFormat, $j.recordLength; '  acknowledge: {0}' -f ([string]$j.sendingAcknowledgmentEnabled).ToLower(); '  advanced:    {0}' -f ([string]$j.advancedSettings.enabled).ToLower(); if ($j.advancedSettings.enabled) { $c = $j.advancedSettings.callerTranscoding; $r = $j.advancedSettings.receiverTranscoding; $e = if ($r.lineEndingFormat) { $r.lineEndingFormat } else { '-' }; '  sending:     {0}, {1} records of {2}' -f $c.type, $c.outputRecordFormat, $c.outputRecordLength; '  receiving:   {0}, line ending {1}' -f $r.type, $e }"
IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"

echo.
echo Only some fields of it:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%PROFILE_ID%" --data-urlencode "fields=name,sendMapping,receiveMapping" ^
  -H "accept: application/json" -H "%REFERER_HEADER%"
echo.
