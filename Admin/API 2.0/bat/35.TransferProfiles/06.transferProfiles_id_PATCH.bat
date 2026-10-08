@echo off
REM ==============================================================================
REM Script Name: 06.transferProfiles_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a transfer profile, using the `/transferProfiles/{id}`
REM endpoint with PATCH: a JSON Patch document that replaces the record length of the receiving side
REM (advancedSettings.receiverTranscoding.outputRecordLength), of the sending side, or the plain recordLength. Unlike PUT
REM (05.transferProfiles_id_PUT.bat), it sends only what changes.
REM
REM Usage:
REM 06.transferProfiles_id_PATCH.bat ACCOUNT NAME [RECORD_LENGTH [SIDE]]
REM
REM   ACCOUNT        the account the profile belongs to
REM   NAME           the profile (it must be the only one with that name)
REM   RECORD_LENGTH  the new record length, 1 to 32767 (default 1024)
REM   SIDE           receiver (default), caller or basic: the receiving side's advanced setting, the sending side's, or the
REM                  plain recordLength. The advanced sides need advancedSettings enabled and a type that has a record length
REM                  (ascii, ebcdic, ascii_predefined, ...: not binary)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the record length before, to put it back with. When the profile has none at that place (advanced settings off, or
REM   a binary side) it says so and sends nothing: confirmed directly, the server answers 204 to a patch of a field that the
REM   side's type does not have, and changes nothing. A PATCH cannot change a side's `type` (400 "Patch operation on read only or
REM   discriminator fields is not permitted."): PUT the profile again for that (05). The record length of a sender is what the
REM   receiver compares each record with: a record longer than it fails the transfer ("Record length too long"), check 59.
REM - Confirmed directly: a success answers 204, with no body, and an empty patch is 204 too. `replace` and `add` of the
REM   scalar fields work (`/sendMapping`, `/receiveMapping`, `/recordLength`, `/default`, `/name`); `add` to
REM   `/additionalAttributes/userVars.<name>` works, the key must start with `userVars.` and the value may not be blank
REM   (400). `replace` of `/account` is 204 and changes nothing; of `/id` 400. A path that does not exist is 400
REM   `Missing field "nope"`, a value out of range or not in the enum is 400 with the reason ("recordLength must be greater
REM   than or equal to 1"), and a patch that would leave no `sendMapping` and no `receiveMapping` is refused, 400. An unknown
REM   id is a JSON 404. `default` true on a profile turns the account's previous default off.
REM - Per the reference, the plain `recordLength` is used only while `advancedSettings.enabled` is false; the advanced lengths
REM   only while it is true (confirmed on transfers in check 59).
REM - PowerShell is used to read the id and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
SET NAME=%~2
IF "%ACCOUNT%"=="" GOTO :usage
IF "%NAME%"=="" GOTO :usage
SET RECORD_LENGTH=%~3
IF "%RECORD_LENGTH%"=="" SET RECORD_LENGTH=1024
SET SIDE=%~4
IF "%SIDE%"=="" SET SIDE=receiver
SET JSON_PATH=
IF /I "%SIDE%"=="receiver" SET JSON_PATH=/advancedSettings/receiverTranscoding/outputRecordLength
IF /I "%SIDE%"=="caller" SET JSON_PATH=/advancedSettings/callerTranscoding/outputRecordLength
IF /I "%SIDE%"=="basic" SET JSON_PATH=/recordLength
IF "%JSON_PATH%"=="" (
    echo SIDE is receiver, caller or basic, not %SIDE%.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:RECORD_LENGTH -match '^[0-9]{1,5}$' -and [int]$env:RECORD_LENGTH -ge 1 -and [int]$env:RECORD_LENGTH -le 32767) { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo RECORD_LENGTH is a number from 1 to 32767, not %RECORD_LENGTH%.
    EXIT /B 2
)
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
SET PROFILE_FILE=%TEMP%\tprof_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%PROFILE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%PROFILE_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the transfer profile %NAME% ^(id %PROFILE_ID%^).
    IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\tprof_patch_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\tprof_response_%RANDOM%.txt
SET BEFORE=
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$j = Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json; if ($env:SIDE -eq 'basic') { $j.recordLength } else { $t = if ($env:SIDE -eq 'caller') { $j.advancedSettings.callerTranscoding } else { $j.advancedSettings.receiverTranscoding }; if ($j.advancedSettings.enabled -and $t.type -ne 'binary') { $t.outputRecordLength } }"') DO SET BEFORE=%%D
IF "%BEFORE%"=="" (
    echo The transfer profile %NAME% has no record length for %SIDE%: its advanced settings are off or that side is binary. Nothing sent.
    IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"
    EXIT /B 1
)
echo The record length of %NAME% ^(%SIDE%^) is now %BEFORE%.
powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = $env:JSON_PATH; value = [int]$env:RECORD_LENGTH }; ConvertTo-Json -InputObject @($op) -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %RECORD_LENGTH%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%PROFILE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:usage
echo Usage: 06.transferProfiles_id_PATCH.bat ACCOUNT NAME [RECORD_LENGTH [SIDE]]
EXIT /B 2
