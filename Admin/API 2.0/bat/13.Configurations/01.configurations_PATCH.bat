@echo off
REM ==============================================================================
REM Script Name: 01.configurations_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes the first value of a Server Configuration Option, using the
REM `/configurations/options/{name}` endpoint with the PATCH method.
REM It demonstrates:
REM - A JSON Patch `replace` of `/values/0`, built with jq
REM - Reading and printing the old value first, with the command that puts it back
REM - The HTTP code, and an exit of 1 when the server refuses
REM
REM Usage:
REM 01.configurations_PATCH.bat VALUE [OPTION]
REM
REM   VALUE   the new value. Required: with no value the script prints this usage, sends NOTHING and exits 2.
REM           For the default option it is true or false
REM   OPTION  the option's name (default AddressBook.Enabled), letters, digits, dots, dashes and underscores
REM
REM Risk: config - changes a Server Configuration Option of the whole server; put it back afterwards (the script prints how)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - An option holds a LIST of values, so the path targets an index: "/values/0" is the first value. Only that one is replaced.
REM - Changing a Server Configuration Option affects the whole server, and the default option is a real feature switch (the address book), so there is no
REM   default value: the value is an argument. The script prints the old values, and the command that puts the first one back, before it changes anything.
REM - PowerShell is used to build the request body and read the old value, in place of jq.
REM - Confirmed directly: PATCH answers 204 with no body; GET of the option with `fields=values` answers `{"values": [...]}`. An option that does not exist is 404 on the
REM   GET ("Configuration option with name X not found") and 400 on the PATCH ("Option with name \"X\" does not exist."). The `readOnly` flag an option carries does not stop
REM   the API: `StatisticsSummaryReport.AutomaticReport.DaysToInclude`, which reads readOnly true, was patched and put back. The server does not check a value against what
REM   the option means (the text "abc" was accepted for that number), so check it yourself; an encrypted option reads back as `{AES128}...` and a plain value sent to it is stored encrypted.
REM - `replace` needs the value to exist. An option that holds no value is refused by this script (nothing sent): set it with 04.configurations_options_PUT.bat.
REM - Exit codes: 0 when the server answered 204, 1 when the option cannot be read or the server refuses, 2 when the value or the option name is missing or wrong (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations/options
SET DEFAULT_OPTION=AddressBook.Enabled
SET USAGE=Usage: 01.configurations_PATCH.bat VALUE [OPTION], with OPTION %DEFAULT_OPTION% when left out
SET "VALUE=%~1"
SET OPTION=%~2
IF "%OPTION%"=="" SET OPTION=%DEFAULT_OPTION%

IF [%1]==[] (
    echo This changes a Server Configuration Option of the whole server. Nothing was sent: it needs the new value.
    echo %USAGE%
    EXIT /B 2
)
IF "%VALUE%"=="" GOTO usage
IF NOT [%3]==[] GOTO usage
powershell -NoProfile -Command "if ($env:OPTION -match '^[A-Za-z0-9._-]+$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
IF "%OPTION%"=="%DEFAULT_OPTION%" IF NOT "%VALUE%"=="true" IF NOT "%VALUE%"=="false" (
    echo VALUE for %OPTION% is true or false.
    GOTO usage
)

SET OPTION_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:OPTION)"') DO SET OPTION_URI=%%E
SET RESPONSE_FILE=%TEMP%\option_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\option_body_%RANDOM%.json

echo Reading the option %OPTION%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%OPTION_URI%" --data-urlencode "fields=values" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read the option %OPTION%: HTTP %HTTP_CODE%
    GOTO refused
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $v = @($r.values | Where-Object { $_ -ne $null }); 'The values of {0} are now: {1}' -f $env:OPTION, (ConvertTo-Json -InputObject $v -Compress); if ($v.Count -eq 0) { exit 1 }; 'To put the first one back: 01.configurations_PATCH.bat ' + [char]34 + $v[0] + [char]34 + ' ' + $env:OPTION"
IF ERRORLEVEL 1 (
    echo The option holds no value, and replace needs one. Nothing was sent: set it with 04.configurations_options_PUT.bat.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

powershell -NoProfile -Command "$op = [ordered]@{ op = 'replace'; path = '/values/0'; value = $env:VALUE }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress))"

powershell -NoProfile -Command "'Setting ' + $env:OPTION + ' to ' + $env:VALUE + '...'"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%OPTION_URI%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" GOTO refused
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0
:refused
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:usage
echo %USAGE%
EXIT /B 2
