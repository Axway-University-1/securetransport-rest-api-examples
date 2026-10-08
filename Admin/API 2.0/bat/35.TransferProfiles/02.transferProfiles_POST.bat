@echo off
REM ==============================================================================
REM Script Name: 02.transferProfiles_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a transfer profile using the `/transferProfiles` endpoint.
REM A profile belongs to an account and tells a PeSIT transfer which file to send, what to call
REM the file it receives, and how the file is labelled. It demonstrates:
REM - A profile with advancedSettings, which is how a profile says what happens to the content of a file: the
REM   sending side (callerTranscoding) and the receiving side (receiverTranscoding) each get a `type`, binary, ascii
REM   or ebcdic. The plain fields (transferMode, recordFormat...) stay as they are and are not used while the advanced
REM   settings are enabled. The word `basic` makes a profile with the plain fields only (the smallest body the server
REM   accepts: name, account, fileLabelOption and one mapping)
REM - Reading the new profile's address from the Location header
REM
REM Usage:
REM 02.transferProfiles_POST.bat [ACCOUNT [NAME [SEND_MAPPING [RECEIVE_MAPPING [TRANSCODING]]]]]
REM
REM   ACCOUNT          the account the profile is for (default john; it needs a PeSIT site)
REM   NAME             the profile's name (default example_profile)
REM   SEND_MAPPING     the file to send (default /example_file.txt)
REM   RECEIVE_MAPPING  what to call a file received; may not contain * or ? (default: none)
REM   TRANSCODING      binary (default), ascii or ebcdic: the advancedSettings type of both sides; or basic, for a
REM                    profile with the plain fields only (no advancedSettings)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Transfer profiles are a PeSIT thing. Confirmed directly: a profile for an account that has no PeSIT transfer site
REM   is refused, 400 "Account does not contain any PeSIT transfer sites."; an account that does not exist is 404.
REM - Run 07.transferProfiles_id_DELETE.bat to remove what this creates.
REM - Confirmed directly (PeSIT pulls on the lab, the bytes read on the wire and in the stored file; check 59): with
REM   `binary` on both sides a file travels and is stored byte for byte. With `ascii` the sender cuts a file into records at
REM   each LF (a CR before it goes too) and the receiver puts an LF after each record: CRLF becomes LF, a final newline is
REM   added when there was none, and a line longer than 2048 bytes makes the transfer fail ("Record length too long").
REM   `ebcdic` sends the bytes as they are and announces them as EBCDIC, ends records at 0x15, and a receiving `ebcdic`
REM   converts ASCII to EBCDIC (IBM1047) only when the sender says the data is ASCII. The server reads the profile back with
REM   the read-only parts filled in (localDataCode, networkDataCode, outputRecordFormat VARIABLE, outputRecordLength 2048,
REM   a paddingCharacter of \u0020 for ascii and \u0040 for ebcdic, lineEndingFormat DEFAULT). `type` is case sensitive and
REM   an unknown one is 400. While `advancedSettings.enabled` is true they win over `transferMode`; set it false and the
REM   plain fields are in force again, whatever the advanced settings hold. The other options (record format and length,
REM   padding character, line ending, the conversions between character sets) are changed with 05 and 06 and tried in check 59.
REM - Confirmed directly: a success is 201 with the new profile's address in `Location` and no body. `fileLabelOption`
REM   (DONT_SEND, SEND_FILENAME or SEND_FILENAME_AND_PATH) is required though the reference's example omits it, and so
REM   are `name` and `account`; at least one of `sendMapping` and `receiveMapping` must be set (400 otherwise). Everything
REM   else has a default: not the default profile, BINARY, Variable records of 2048, no acknowledgment, no padding strip,
REM   `receiveMapping` an empty string. A second profile with the same account and name is 400 "The transfer profile
REM   cannot have the same account and name.", but names are case sensitive (`p1` and `P1` coexist) and the same name on
REM   another account is fine. A name with a space is accepted; a name of 300 characters is a 403 "unable to comply".
REM   The server stores a `/` in front of both mappings: `in.txt` reads back `/in.txt`, and a relative or an absolute
REM   `receiveMapping` lands the file in the same place (the pull's destination directory). `sendMapping` is 250 characters at
REM   most, `recordLength` 1 to 32767. `receiveMapping` may not contain `*` or `?` (400); `sendMapping` may (`/*`).
REM   `default` true turns the account's previous default off. Deleting the account deletes its profiles.
REM - PowerShell is used to build the request body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/transferProfiles
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=example_profile
SET SEND_MAPPING=%~3
IF "%SEND_MAPPING%"=="" SET SEND_MAPPING=/example_file.txt
SET RECEIVE_MAPPING=%~4
SET TRANSCODING=%~5
IF "%TRANSCODING%"=="" SET TRANSCODING=binary
IF "%NAME: =%"=="" (
    echo NAME must not be empty.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:RECEIVE_MAPPING -match '[*?]') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo RECEIVE_MAPPING may not contain * or ?: %RECEIVE_MAPPING%
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:SEND_MAPPING.Length -gt 250) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo SEND_MAPPING is 250 characters at most.
    EXIT /B 2
)
IF /I NOT "%TRANSCODING%"=="binary" IF /I NOT "%TRANSCODING%"=="ascii" IF /I NOT "%TRANSCODING%"=="ebcdic" IF /I NOT "%TRANSCODING%"=="basic" (
    echo TRANSCODING is binary, ascii, ebcdic or basic, not %TRANSCODING%.
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\tprof_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\tprof_response_%RANDOM%.txt
SET HEADERS_FILE=%TEMP%\tprof_headers_%RANDOM%.txt

REM receiveMapping is left out when there is none; advancedSettings when the profile is basic
powershell -NoProfile -Command "$b = [ordered]@{ name = $env:NAME; account = $env:ACCOUNT; sendMapping = $env:SEND_MAPPING; fileLabelOption = 'DONT_SEND' }; if ($env:RECEIVE_MAPPING) { $b.receiveMapping = $env:RECEIVE_MAPPING }; $t = $env:TRANSCODING.ToLower(); if ($t -ne 'basic') { $b.advancedSettings = [ordered]@{ enabled = $true; callerTranscoding = [ordered]@{ type = $t }; receiverTranscoding = [ordered]@{ type = $t } } }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 6))"

echo Creating the transfer profile %NAME% for %ACCOUNT% ^(%TRANSCODING%^)...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
