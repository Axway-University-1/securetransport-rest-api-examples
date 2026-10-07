@echo off
REM ==============================================================================
REM Script Name: 01.routeStepsCharsets_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the character sets a route step can use, with the
REM `/routeStepsCharsets` endpoint.
REM It demonstrates:
REM - Counting the character sets and listing them, one per line
REM - Asking whether one name is in the list
REM - Checking the `inputCharset` and `outputCharset` of a route step (or of every step of a route) in a JSON file
REM   against the list, before the step is sent to the server
REM
REM Usage:
REM 01.routeStepsCharsets_GET.bat [CHARSET | step FILE]
REM
REM   CHARSET  a character set name to look for, as written, e.g. UTF-8 (optional)
REM   step FILE  a JSON file holding one step, an array of steps, or a route with a `steps` array: every
REM              inputCharset and outputCharset in it is looked up, one line each (optional)
REM
REM Risk: read - the only operation of this resource is a GET
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print one name per line and read the step file, in place of jq.
REM - Confirmed directly: the answer is NOT an array and NOT {resultSet, result}: it is one object, {"charsets": [...]},
REM   as the reference says. The lab lists 396 names, all different, sorted ignoring case (`Big5` first). It holds the
REM   names the steps use (UTF-8, UTF-16, US-ASCII, ISO-8859-1, windows-1252) and the EBCDIC pages (IBM037, IBM1047).
REM - Confirmed directly: the list is of the canonical names only, and is NOT what the server accepts. A route step
REM   whose charset is not a charset the server's Java knows (`NOPE-9`) is refused, 400 "The charset specified by
REM   inputCharset is not supported." (the same for outputCharset, on CharactersReplace, EncodingConversion,
REM   LineEnding, LineFolding, LinePadding and LineTruncating); an empty one is 400 "The charset name specified by
REM   inputCharset is illegal.". But `utf-8` (lower case), `UTF8` and `ASCII`, none of them in the list, are accepted
REM   (201) and stored as written. So a name in the list is always accepted; a name outside it may be too. This script
REM   compares exactly, as written, and says when the name differs from a listed one only in case.
REM - Confirmed directly: the 11 step types that name no charset (Compress, Rename ...) ignore the list. Of the 17 steps
REM   the 30.RouteStepsMetadata example prints with `minimal`, 6 types hold an inputCharset (UTF-8) and one,
REM   EncodingConversion, an outputCharset (UTF-16); all are in the list: run `step FILE` on the output of that script.
REM - Confirmed directly: the endpoint has no filter. name=, limit=, offset= and fields= are ignored and the whole list
REM   is answered. HEAD is 200; POST, PUT, PATCH and DELETE are 405, /routeStepsCharsets/UTF-8 is 404, and
REM   Accept: application/xml and text/csv are 406.
REM - Exit codes: 0 when the name (or every charset in the file) is in the list, 1 when not, or when the server refuses,
REM   2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routeStepsCharsets
SET MODE=%~1
SET FILE=%~2
SET RESPONSE_FILE=%TEMP%\charsets_%RANDOM%.json

IF /I "%MODE%"=="step" GOTO check_step
IF NOT "%FILE%"=="" GOTO usage
GOTO args_ok
:usage
echo Usage: 01.routeStepsCharsets_GET.bat [CHARSET ^| step FILE]
EXIT /B 2
:check_step
IF "%FILE%"=="" GOTO step_file
IF NOT EXIST "%FILE%" GOTO step_file
IF NOT "%~3"=="" GOTO step_file
powershell -NoProfile -Command "try { Get-Content -Raw $env:FILE | ConvertFrom-Json | Out-Null } catch { exit 2 }"
IF ERRORLEVEL 1 (
    echo %FILE% is not JSON.
    EXIT /B 2
)
GOTO args_ok
:step_file
echo step needs the name of a file that exists.
GOTO usage
:args_ok

FOR /F %%C IN ('curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -o "%RESPONSE_FILE%" -w "%%{http_code}"') DO SET CODE=%%C

IF NOT "%CODE%"=="200" (
    echo HTTP %CODE%
    IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

IF /I "%MODE%"=="step" GOTO step
IF NOT "%MODE%"=="" GOTO one

FOR /F %%N IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).charsets).Count"') DO echo Character sets: %%N
powershell -NoProfile -Command "foreach ($c in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).charsets)) { '  ' + $c }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:one
powershell -NoProfile -Command "$l = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).charsets); if ($l -ccontains $env:MODE) { Write-Output ($env:MODE + ' is in the list.'); exit 0 }; $s = $l | Where-Object { $_ -ieq $env:MODE } | Select-Object -First 1; if ($s) { Write-Output ($env:MODE + ' is not in the list as written; the list has ' + $s + '.') } else { Write-Output ($env:MODE + ' is not in the list.') }; exit 1"
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:step
powershell -NoProfile -Command "$l = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).charsets); $j = Get-Content -Raw $env:FILE | ConvertFrom-Json; if ($j -is [array]) { $steps = @($j) } elseif ($j.PSObject.Properties['steps']) { $steps = @($j.steps) } else { $steps = @($j) }; $n = 0; $bad = 0; for ($i = 0; $i -lt $steps.Count; $i++) { $s = $steps[$i]; if ($s -isnot [psobject]) { continue }; foreach ($f in 'inputCharset', 'outputCharset') { $p = $s.PSObject.Properties[$f]; if ($p -and $null -ne $p.Value) { $n++; $t = $s.type; if (-not $t) { $t = '-' }; if ($l -ccontains [string]$p.Value) { $r = 'listed' } else { $r = 'NOT listed'; $bad++ }; Write-Output ('  step {0} {1} {2} {3}: {4}' -f $i, $t, $f, $p.Value, $r) } } }; if ($n -eq 0) { Write-Output ('No inputCharset or outputCharset in ' + $env:FILE + ': nothing to check.') }; if ($bad -gt 0) { exit 1 }; exit 0"
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%
