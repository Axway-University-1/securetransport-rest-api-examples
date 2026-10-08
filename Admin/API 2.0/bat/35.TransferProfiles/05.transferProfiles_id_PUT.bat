@echo off
REM ==============================================================================
REM Script Name: 05.transferProfiles_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a transfer profile, using the `/transferProfiles/{id}` endpoint with PUT:
REM it reads the profile, changes the line ending of the receiving side (advancedSettings.receiverTranscoding.lineEndingFormat)
REM and, when asked, the file it sends (sendMapping, a plain field), and sends the whole profile back.
REM
REM Usage:
REM 05.transferProfiles_id_PUT.bat ACCOUNT NAME [LINE_ENDING [SEND_MAPPING]]
REM
REM   ACCOUNT       the account the profile belongs to
REM   NAME          the profile (it must be the only one with that name)
REM   LINE_ENDING   DEFAULT, UNIX or WINDOWS (default WINDOWS): what a receiving ascii, ebcdic or predefined side ends each record
REM                 with. - leaves it alone. The profile needs advancedSettings enabled and such a receiving side (02 ... ascii)
REM   SEND_MAPPING  the new file to send, as well (250 characters at most). Without LINE_ENDING use - : 05 ... NAME - /new.txt
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the values before, to put them back with. A profile whose advanced settings are off, or whose receiving side is
REM   binary, has no line ending to change: the script says so and sends nothing (the server would answer 204 and ignore it,
REM   confirmed directly). `type` cannot be changed by PATCH (400, a discriminator) but a PUT with another type works, and the
REM   fields that belong to the old type are dropped.
REM - PUT replaces the whole profile, and the body needs the profile's `id`. Confirmed directly: a body without it is 400
REM   "id to load is required for loading", and a hand-built fragment WITH the id (name, account, sendMapping, fileLabelOption)
REM   answers 204 and silently resets everything it leaves out: transferMode, recordFormat, recordLength, multiSelect,
REM   the acknowledgment and padding flags, the additional attributes. That is why the profile is read first and sent back with
REM   one field changed. `metadata`, the read-only link, is left out.
REM - Confirmed directly: a success answers 204, with no body. `default` in the body is applied (true turns the account's
REM   previous default off). `account` in the body is accepted and ignored; `name` renames the profile; a name the account
REM   already has is a 403 "unable to comply" (not 400). An unknown id is a JSON 404, and a body without `fileLabelOption` 400.
REM - PowerShell is used to read the id and edit the profile, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
SET NAME=%~2
IF "%ACCOUNT%"=="" GOTO :usage
IF "%NAME%"=="" GOTO :usage
SET LINE_ENDING=%~3
IF "%LINE_ENDING%"=="" SET LINE_ENDING=WINDOWS
SET SEND_MAPPING=%~4
IF /I NOT "%LINE_ENDING%"=="DEFAULT" IF /I NOT "%LINE_ENDING%"=="UNIX" IF /I NOT "%LINE_ENDING%"=="WINDOWS" IF NOT "%LINE_ENDING%"=="-" (
    echo LINE_ENDING is DEFAULT, UNIX, WINDOWS or -, not %LINE_ENDING%.
    EXIT /B 2
)
IF "%LINE_ENDING%"=="-" IF "%SEND_MAPPING%"=="" (
    echo Nothing to change: give a LINE_ENDING or a SEND_MAPPING.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:SEND_MAPPING.Length -gt 250) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo SEND_MAPPING is 250 characters at most.
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
SET BODY_FILE=%TEMP%\tprof_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\tprof_response_%RANDOM%.txt
IF "%LINE_ENDING%"=="-" GOTO :ending_done
SET BEFORE=
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$j = Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json; $r = $j.advancedSettings.receiverTranscoding; if ($j.advancedSettings.enabled -and @('ascii','ebcdic','predefined','custom_table') -contains $r.type) { $r.lineEndingFormat }"') DO SET BEFORE=%%D
IF "%BEFORE%"=="" (
    echo The transfer profile %NAME% has no receiving line ending: its advanced settings are off or its receiving side is binary. Nothing sent.
    IF EXIST "%PROFILE_FILE%" DEL "%PROFILE_FILE%"
    EXIT /B 1
)
echo The lineEndingFormat of %NAME% is now %BEFORE%.
:ending_done
IF NOT "%SEND_MAPPING%"=="" FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json).sendMapping"') DO echo The sendMapping of %NAME% is now %%D.
powershell -NoProfile -Command "$p = Get-Content -Raw $env:PROFILE_FILE | ConvertFrom-Json; if ($env:LINE_ENDING -ne '-') { $p.advancedSettings.receiverTranscoding.lineEndingFormat = $env:LINE_ENDING.ToUpper() }; if ($env:SEND_MAPPING) { $p.sendMapping = $env:SEND_MAPPING }; $p.PSObject.Properties.Remove('metadata'); $p | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Changing it...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%PROFILE_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
echo Usage: 05.transferProfiles_id_PUT.bat ACCOUNT NAME [LINE_ENDING [SEND_MAPPING]]
EXIT /B 2
