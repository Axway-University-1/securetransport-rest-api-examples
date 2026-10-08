@echo off
REM ==============================================================================
REM Script Name: 01.zones_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves network zones using the `/zones` endpoint.
REM It demonstrates:
REM - The number of zones on the server
REM - The zone matching a name, or every zone, one line each: default, number of edges, description
REM - Only the default zone, if there is one
REM
REM Usage:
REM 01.zones_GET.bat [NAME]
REM
REM   NAME  list only the zone with this exact name (default every zone)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A zone is a NETWORK ZONE (a DMZ zone): it describes where the server's protocol servers are reached from. The lab has one,
REM   `Private` ("This network zone holds the information for back ends", one edge `Host` with the lab's own FTP, SSH, HTTP, ADMIN,
REM   AS2 and PESIT ports); a DMZ zone lists its edge servers in `edges` (title, addresses, protocols with ports, proxies). A zone is
REM   addressed by its NAME in the path, and the name is case sensitive (`Private` is found, `private` is a 404). Never change or
REM   delete `Private`: the examples default to an `example_*` zone, and the ones that change something need the name.
REM - Confirmed directly: the answer is `{resultSet, result}`. `name=` is EXACT and case sensitive (no `*`: `example*` and `EXAMPLE_ZONE` find
REM   nothing), and this script also keeps only the zone whose name is exactly NAME. `isDefault=` takes true or false (another text lists every
REM   zone). `description=`, `publicURLPrefix=`, `isDnsResolutionEnabled=` and the `edges.*` filters (`edges.title`, `edges.protocols.port`,
REM   `edges.protocols.streamingProtocol`, `edges.ipAddresses.ipAddress`, `edges.proxies.username`, `edges.enabledProxy`) work, exactly; an unknown
REM   filter is ignored (200), but `edges.proxies.isUsePassword=` answers 403 "unable to comply". `limit=0` lists all, a negative one is 400 "The limit
REM   should be a positive number or 0.", `limit=abc` and a negative `offset` are 400; `limit=1&offset=N` walked three zones once each. `fields=` keeps
REM   the keys named; an unknown one is 400 "Field bogus does not exist.".
REM - PowerShell is used to print one line per zone, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
SET RESPONSE_FILE=%TEMP%\zones_%RANDOM%.json
SET SHOWN=%NAME%
IF "%SHOWN%"=="" SET "SHOWN=(any)"
SET NAME_FILTER=
IF NOT "%NAME%"=="" SET NAME_FILTER=--data-urlencode "name=%NAME%"

<nul set /p "=Zones on the server: "
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?limit=1&fields=name" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"

echo.
echo The zones named %SHOWN%: name, default, edges, description:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" %NAME_FILTER% --data-urlencode "limit=0" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($z in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($z -and ($env:NAME -eq '' -or $z.name -ceq $env:NAME)) { '  {0}  default {1}  edges {2}  {3}' -f $z.name, ([string]$z.isDefault).ToLower(), ($z.edges | Measure-Object).Count, $(if ($z.description) { $z.description } else { '-' }) } }"

echo.
echo The default zone:
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "isDefault=true" --data-urlencode "limit=0" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
powershell -NoProfile -Command "foreach ($z in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($z -and $z.isDefault) { '  {0}  default {1}  edges {2}  {3}' -f $z.name, ([string]$z.isDefault).ToLower(), ($z.edges | Measure-Object).Count, $(if ($z.description) { $z.description } else { '-' }) } }"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
