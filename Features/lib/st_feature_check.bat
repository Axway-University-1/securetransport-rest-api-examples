@echo off
REM ==============================================================================
REM Script Name: st_feature_check.bat
REM Author: Plamen Milenkov
REM Created: 2026-09-30
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Shared by every feature example. Loads the connection settings, asks the
REM server for its version with GET /version, and compares it with the version
REM in which the feature was introduced.
REM
REM Sets ERRORLEVEL so the calling example can decide:
REM   0   the server is at or after that version: carry on
REM   10  the server is before that version: skip the example
REM   11  the version cannot be determined: stop with an error
REM
REM Usage:
REM Call it near the top of an example, passing the version that introduced the
REM feature, then act on the result:
REM
REM   CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
REM   IF ERRORLEVEL 11 EXIT /B 1
REM   IF ERRORLEVEL 10 EXIT /B 0
REM
REM Version format:
REM <major>.<minor>[-<YYYYMMDD>], for example 5.5 or 5.5-20260924. A date with
REM only the month (5.5-202609) is also accepted and counts as the start of that
REM month. A server that reports no date part is treated as the base release, so
REM it is older than any dated update of the same release.
REM
REM Notes:
REM - Uses the same set_variables.bat as the Admin examples.
REM - Uses PowerShell to read the JSON and compare the versions.
REM ==============================================================================

SET ST_REQUIRED_VERSION=%~1
CALL "%~dp0..\..\Admin\API 2.0\bat\set_variables.bat"

SET REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET VERSION_FILE=%TEMP%\st_feature_version_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/version" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%VERSION_FILE%"

powershell -NoProfile -Command ^
  "function Key($t) { if ($t -match '^(\d+)\.(\d+)(\.\d+)?(-(\d{6}(\d{2})?))?') { $u = 0; if ($Matches[5]) { $u = [int]$Matches[5]; if ($Matches[5].Length -eq 6) { $u = $u * 100 } }; return '{0:D3}{1:D3}{2:D8}' -f [int]$Matches[1], [int]$Matches[2], $u } return $null };" ^
  "$required = Key '%ST_REQUIRED_VERSION%';" ^
  "if (-not $required) { Write-Host \"ERROR: '%ST_REQUIRED_VERSION%' is not a version this check understands. Use e.g. 5.5-20260924.\"; exit 11 };" ^
  "$text = $null; try { $text = (Get-Content -Raw '%VERSION_FILE%' | ConvertFrom-Json).version } catch { };" ^
  "$server = Key $text;" ^
  "if (-not $server) { Write-Host 'ERROR: could not read a version from GET /version. Check the server, port and credentials.'; exit 11 };" ^
  "if ([string]::CompareOrdinal($server, $required) -lt 0) { Write-Host \"SKIPPED: this feature needs SecureTransport %ST_REQUIRED_VERSION% or later. This server is $text.\"; exit 10 };" ^
  "Write-Host \"Version check passed: server $text, feature needs %ST_REQUIRED_VERSION%.\"; exit 0"

SET ST_CHECK_RESULT=%ERRORLEVEL%
IF EXIST "%VERSION_FILE%" DEL "%VERSION_FILE%"
EXIT /B %ST_CHECK_RESULT%
