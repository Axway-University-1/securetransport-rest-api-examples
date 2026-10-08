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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\tprof_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=TP
IF NOT "%~3"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET PROFILE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET PROFILE_ID=%%B
)
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% transfer profiles named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)

echo The transfer profile %NAME% of %ACCOUNT%, id %PROFILE_ID%:
SET "URL=%MAIN_URL%/%PROFILE_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the transfer profile %NAME% ^(id %PROFILE_ID%^).
    EXIT /B 1
)
powershell -NoProfile -Command "$j = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  default:     {0}' -f ([string]$j.default).ToLower(); '  send:        {0}' -f $j.sendMapping; '  receive:     {0}' -f $j.receiveMapping; '  file label:  {0}' -f $j.fileLabelOption; '  mode:        {0}, {1} records of {2}' -f $j.transferMode, $j.recordFormat, $j.recordLength; '  acknowledge: {0}' -f ([string]$j.sendingAcknowledgmentEnabled).ToLower(); '  advanced:    {0}' -f ([string]$j.advancedSettings.enabled).ToLower(); if ($j.advancedSettings.enabled) { $c = $j.advancedSettings.callerTranscoding; $r = $j.advancedSettings.receiverTranscoding; $e = if ($r.lineEndingFormat) { $r.lineEndingFormat } else { '-' }; '  sending:     {0}, {1} records of {2}' -f $c.type, $c.outputRecordFormat, $c.outputRecordLength; '  receiving:   {0}, line ending {1}' -f $r.type, $e }"

echo.
echo Only some fields of it:
SET "URL=%MAIN_URL%/%PROFILE_ID%"
SET CURL_OPTS=-G --data-urlencode "fields=name,sendMapping,receiveMapping"
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
echo Usage: 04.transferProfiles_id_GET.bat [ACCOUNT [NAME]]
EXIT /B 2
