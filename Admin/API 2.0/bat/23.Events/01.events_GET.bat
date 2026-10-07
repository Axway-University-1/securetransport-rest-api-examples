@echo off
REM ==============================================================================
REM Script Name: 01.events_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the events using the `/events` endpoint: the tasks SecureTransport
REM is processing right now, such as an Advanced Routing run for a file that has
REM arrived. It demonstrates:
REM - Counting them
REM - Searching by account, with the * wildcard, and by status
REM - Only the Advanced Routing ones, with processorType=
REM - Only the ones with a heartbeat in the last hour, with lastHeartbeatAfter=
REM
REM Usage:
REM 01.events_GET.bat [ACCOUNT_PATTERN [STATUS]]
REM
REM   ACCOUNT_PATTERN  an account name, * matches anything (default *)
REM   STATUS           only the events with this status, for example active (optional)
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The list is usually empty: an event lives only while a file is being processed.
REM   One whose partner does not answer stays for as long as the server waits.
REM - Confirmed directly: the answer is {resultSet, result}. An event's id looks like
REM   0x000001A114DB4957...; each entry has status, accountName, fullTarget (the file),
REM   agentType, processorType, retryCount, arrivalTime and lastHeartbeat.
REM - Confirmed directly: a new event is ready while it waits to be taken, then active
REM   while it runs; a ready one has no heartbeat yet. status is matched exactly:
REM   active finds events, ACTIVE none.
REM   A processorType that does not exist is not refused, it just finds nothing.
REM - Confirmed directly: arrivalTime, lastHeartbeatAfter and lastHeartbeatBefore are
REM   timestamps in milliseconds; a date such as 2026-10-07 answers 400 "For input
REM   string".
REM - Confirmed directly: a file's arrival can show a short-lived event of its own,
REM   processorType DEFAULT, before the Advanced Routing one; processorType= tells them
REM   apart.
REM - An event can stay active after its transfer has failed. 03.events_operations_POST_delete.bat
REM   removes it.
REM - PowerShell is used to print one event per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/events
SET ACCOUNT_PATTERN=%~1
IF "%ACCOUNT_PATTERN%"=="" SET ACCOUNT_PATTERN=*
SET STATUS=%~2
SET RESPONSE_FILE=%TEMP%\events_%RANDOM%.json

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=id" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Events: %%N

echo.
echo The events of the accounts matching %ACCOUNT_PATTERN%: id, status, account, file, retries:
IF "%STATUS%"=="" (
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "accountName=%ACCOUNT_PATTERN%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
) ELSE (
    curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "accountName=%ACCOUNT_PATTERN%" --data-urlencode "status=%STATUS%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($e in $r.result) { $a = if ($e.accountName) { $e.accountName } else { '-' }; $t = if ($e.fullTarget) { $e.fullTarget } else { '-' }; '  {0}  {1}  {2}  {3}  retries {4}' -f $e.id, $e.status, $a, $t, $e.retryCount }"

echo.
echo Only the Advanced Routing ones:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "accountName=%ACCOUNT_PATTERN%" ^
  --data-urlencode "processorType=ADVANCED_ROUTING" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($e in $r.result) { $a = if ($e.accountName) { $e.accountName } else { '-' }; $t = if ($e.fullTarget) { $e.fullTarget } else { '-' }; '  {0}  {1}  {2}  {3}  retries {4}' -f $e.id, $e.status, $a, $t, $e.retryCount }"

REM The last hour, as a timestamp in milliseconds
FOR /F %%S IN ('powershell -NoProfile -Command "[DateTimeOffset]::UtcNow.AddHours(-1).ToUnixTimeMilliseconds()"') DO SET SINCE=%%S
echo.
echo With a heartbeat in the last hour:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "accountName=%ACCOUNT_PATTERN%" ^
  --data-urlencode "lastHeartbeatAfter=%SINCE%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; foreach ($e in $r.result) { $a = if ($e.accountName) { $e.accountName } else { '-' }; $t = if ($e.fullTarget) { $e.fullTarget } else { '-' }; '  {0}  {1}  {2}  {3}  retries {4}' -f $e.id, $e.status, $a, $t, $e.retryCount }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
