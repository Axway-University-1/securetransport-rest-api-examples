@echo off
REM ==============================================================================
REM Script Name: 01.statisticsSummary_generateReport_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script generates the statistics summary report, using the `/statisticsSummary/generateReport`
REM endpoint: the transfers in and out of the server, one line for each day of a period. It is the report
REM the server can send to the Axway Platform for usage reporting, made now, for the dates you give.
REM It demonstrates:
REM - Reading one day, or a period, and printing one line per day and the totals
REM - Asking for the active users count and the incoming file volume
REM
REM Usage:
REM 01.statisticsSummary_generateReport_GET.bat [START [END [ACTIVE_USERS [VOLUME]]]]
REM
REM   START         first day, dd/MM/yyyy (default: today)
REM   END           last day, dd/MM/yyyy, included (default: START)
REM   ACTIVE_USERS  true to ask for the count of active users (optional, default false)
REM   VOLUME        true to ask for the incoming file volume (optional, default false)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to print one line per day, and the totals, in place of jq.
REM - Confirmed directly: both dates are required (400 "'startDate' and 'endDate' parameters are mandatory.") and are
REM   dd/MM/yyyy only (`2026-10-01` and `01-10-2026` are 400 "... is not in correct format"; `1/10/2026` is accepted).
REM   The END day is INCLUDED: START and END the same day gives that one day. The report has one entry for each day,
REM   `granularity` 86400000 (a day, in milliseconds), keyed by the start of the day in the SERVER's time zone with its
REM   offset (`2026-10-07T00:00:00.000+03:00`; the offset changes over a change to summer time). A day with no
REM   transfers is there with zeros, and so is a period years back.
REM - Confirmed directly: a START after END is 400 "Incorrect date frame. 'startDate' must be before 'endDate'.", and an END
REM   after today, a day that does not exist (`32/10/2026`) or START in the future is 400 "An error occur while generating
REM   report for the following date frame". The reference gives no limit on the length of a period: a period of nine months
REM   was answered at once.
REM - Confirmed directly what the numbers are, by uploading and downloading with a test account and reading today's day
REM   again: they follow the server within seconds (they are not cached or periodic). `ST.TransfersIn` goes up by one for
REM   each file received, `ST.TransfersOut` by one for each file sent (a download over the EndUser API or FTP; a file
REM   deleted through the API or FTP is logged as an outgoing transfer but is NOT counted). `ST.Transfers` is the number
REM   to bill: it counts every inbound, the first outbound of a file's chain not at all and every later outbound: an
REM   upload then two downloads gave In +1, Out +2, Transfers +2, so it is not In + Out. It can be larger than `ST.TransfersIn`
REM   and smaller than the sum.
REM - Confirmed directly: `ST.ActiveUsers` and `ST.Volume` read 0 on the lab in every call, also with
REM   includeActiveUsersCount=true and includeIncomingFileVolume=true (and with the other spellings, 1, yes, TRUE, which
REM   are accepted without complaint, as is `abc`), a 3 MB EndUser API upload, a 1 MB FTP upload and many logins that day. The
REM   reference says they are 0 unless asked for; what makes them non-zero was not seen, so do not rely on them.
REM - The answer also holds `envId`, `schemaId`, `timestamp` and a `meta` object: company name, product name and version,
REM   the patch level, `isECEnabled`, `isADIEnabled`, the installed plugins, the time frame and the `reportSummary` (the
REM   totals over the period, the same keys as a day's `usage`). Each day's own `meta` is `{}`. The reference's
REM   `report` is a map keyed by day, not an array.
REM   `meta.reportTimeframe` ends at the start of the day AFTER END (END 08/10 gives `2026-10-09T00:00:00`).
REM - HEAD answers 400 (no dates); POST is 405.
REM - Exit codes: 0 when the server answered 200, 1 when it refuses, 2 for a wrong argument (nothing is sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/statisticsSummary/generateReport
SET START=%~1
IF "%START%"=="" (
    SET DATE_FORMAT=dd/MM/yyyy
    FOR /F %%D IN ('powershell -NoProfile -Command "(Get-Date).ToString($env:DATE_FORMAT, [Globalization.CultureInfo]::InvariantCulture)"') DO SET START=%%D
)
SET END=%~2
IF "%END%"=="" SET END=%START%
SET ACTIVE_USERS=%~3
IF "%ACTIVE_USERS%"=="" SET ACTIVE_USERS=false
SET VOLUME=%~4
IF "%VOLUME%"=="" SET VOLUME=false
IF NOT "%~5"=="" GOTO usage
powershell -NoProfile -Command "if ($env:START -match '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' -and $env:END -match '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' -and $env:ACTIVE_USERS -cmatch '^(true|false)$' -and $env:VOLUME -cmatch '^(true|false)$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 GOTO usage
GOTO args_ok
:usage
echo Usage: 01.statisticsSummary_generateReport_GET.bat [START [END [ACTIVE_USERS [VOLUME]]]]   ^(dates are dd/MM/yyyy, the last two true or false^)
EXIT /B 2
:args_ok
SET RESPONSE_FILE=%TEMP%\statsum_%RANDOM%.json

SET EXTRA=
IF "%ACTIVE_USERS%"=="true" SET EXTRA=%EXTRA% --data-urlencode "includeActiveUsersCount=true"
IF "%VOLUME%"=="true" SET EXTRA=%EXTRA% --data-urlencode "includeIncomingFileVolume=true"

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET -G "%MAIN_URL%" --data-urlencode "startDate=%START%" --data-urlencode "endDate=%END%" %EXTRA% -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo HTTP %HTTP_CODE%
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.message) { $r.message } } catch { }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

powershell -NoProfile -Command "function n($v) { if ($null -eq $v) { 0 } else { $v } }; $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $days = @($r.report.PSObject.Properties | Sort-Object Name); 'Statistics summary of {0} {1}, environment {2}, one entry per {3} hours' -f $r.meta.productName, $r.meta.productVersion, $r.envId, ($r.granularity / 3600000); 'Period: {0} to {1} ({2} days)' -f $r.meta.reportTimeframe.startDate, $r.meta.reportTimeframe.endDate, $days.Count; ''; 'Day, transfers in, out, billable transfers, active users, volume:'; foreach ($d in $days) { $u = $d.Value.usage; '  {0}  in {1}  out {2}  transfers {3}  users {4}  volume {5}' -f $d.Name.Substring(0, 10), (n $u.'ST.TransfersIn'), (n $u.'ST.TransfersOut'), (n $u.'ST.Transfers'), (n $u.'ST.ActiveUsers'), (n $u.'ST.Volume') }; ''; $t = $r.meta.reportSummary; 'Total: in {0}  out {1}  transfers {2}  users {3}  volume {4}' -f (n $t.'ST.TransfersIn'), (n $t.'ST.TransfersOut'), (n $t.'ST.Transfers'), (n $t.'ST.ActiveUsers'), (n $t.'ST.Volume')"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
