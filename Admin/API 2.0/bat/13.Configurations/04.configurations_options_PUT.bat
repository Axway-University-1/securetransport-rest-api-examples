@echo off
REM ==============================================================================
REM Script Name: 04.configurations_options_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes several Server Configuration Options in one call, using
REM the `/configurations/options` endpoint with PUT: a list of names, each with
REM its new values.
REM
REM Usage:
REM 04.configurations_options_PUT.bat NAME=VALUE...
REM
REM   NAME=VALUE  an option and its new value, one argument each (default:
REM               AddressBook.Limit.DefaultDisplayEntries=10 and
REM               AddressBook.Limit.MaxDisplayEntries=100, their usual values)
REM
REM Risk: config
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A configuration applies to the whole server: every account and every user.
REM - It prints each option's values before the change, to put them back with.
REM - Only values change; a name that does not exist answers 404 and nothing is
REM   changed.
REM - To clear an option, send an empty string: NAME= sends [""]. An empty list
REM   answers 400 "Invalid argument length."
REM - 01.configurations_PATCH.bat changes one option with PATCH.
REM - PowerShell is used to build the body and read the options, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations
SET PAIRS=%*
IF "%PAIRS%"=="" SET PAIRS="AddressBook.Limit.DefaultDisplayEntries=10" "AddressBook.Limit.MaxDisplayEntries=100"
SET RESPONSE_FILE=%TEMP%\conf_%RANDOM%.json
SET BODY_FILE=%TEMP%\conf_body_%RANDOM%.json

REM [{"name": NAME, "values": [VALUE]}, ...], from the NAME=VALUE arguments
powershell -NoProfile -Command "$pairs = [regex]::Matches($env:PAIRS, '\"([^\"]*)\"|(\S+)') | ForEach-Object { if ($_.Groups[1].Success) { $_.Groups[1].Value } else { $_.Groups[2].Value } }; $bad = @($pairs | Where-Object { $_ -notmatch '=' }); if ($bad.Count) { Write-Output ('Each argument is NAME=VALUE, not ' + $bad[0]); exit 2 }; $body = @($pairs | ForEach-Object { $n, $v = $_ -split '=', 2; [ordered]@{ name = $n; values = @($v) } }); ConvertTo-Json -Compress -Depth 5 -InputObject $body | Set-Content -Encoding ASCII $env:BODY_FILE"
IF ERRORLEVEL 2 EXIT /B 2

echo Before:
powershell -NoProfile -Command "foreach ($o in (Get-Content -Raw $env:BODY_FILE | ConvertFrom-Json)) { $a = curl.exe -s -k -u ($env:ST_USER + ':' + $env:ST_PASSWORD) -H 'accept: application/json' -H $env:REFERER_HEADER ($env:MAIN_URL + '/options/' + $o.name + '?fields=name,values') | ConvertFrom-Json; '  {0} = {1}' -f $o.name, ($a.values -join ', ') }"
echo Setting:
powershell -NoProfile -Command "foreach ($o in (Get-Content -Raw $env:BODY_FILE | ConvertFrom-Json)) { '  {0} = {1}' -f $o.name, ($o.values -join ', ') }"
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/options" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"'') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
