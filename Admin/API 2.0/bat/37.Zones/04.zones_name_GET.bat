@echo off
REM ==============================================================================
REM Script Name: 04.zones_name_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script retrieves one zone using the `/zones/{name}` endpoint.
REM It demonstrates:
REM - Reading a zone by name, in full
REM - A short summary: the edges with their protocols, proxies and addresses
REM - Which business units name the zone (a business unit's `dmz` is the name of a zone)
REM
REM Usage:
REM 04.zones_name_GET.bat [NAME]
REM
REM   NAME  the zone (default example_zone, which 02 creates)
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
REM - Confirmed directly: the answer is the zone itself: name, description, publicURLPrefix, ssoSpEntityId, isDnsResolutionEnabled, isDefault and
REM   `edges`; an edge has edgeId, title, notes, deploymentSite, enabledProxy, configurationId, descriptor, protocols, proxies, isAutoDiscoverable,
REM   dynamicNodeIpDiscoveryFqdn and ipAddresses. A proxy's `password` is always `null`; `isUsePassword` says whether one is saved. `fields=` keeps the
REM   keys named (400 "Field bogus does not exist." for an unknown one). An unknown zone is a JSON 404 "Zone with name X not found.".
REM - Confirmed directly: **using a zone**. A business unit names a zone in `dmz` (`POST /businessUnits` with `"dmz": "<zone>"`; a zone that does not
REM   exist is 400 "No such DMZ zone with name X"). On the lab, with a zone that has an edge, an account of that unit logged in over SFTP and over the
REM   EndUser API (HTTP) exactly as before: a zone does nothing to a login on a standalone server with no edge in front of it. What it does do: the zone
REM   cannot be deleted while a unit names it (500 "Database error deleting DMZ zone"; delete works again once the unit is gone), and a
REM   unit created while a zone was the default still read `dmz` null (the default flag is not copied into new units). The business units' own
REM   `dmz=` filter answers 403 "unable to comply", so this script reads every unit's `dmz` and picks the ones that name the zone (the first 1000).
REM - PowerShell is used to URL-encode the name and print the summary, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_zone
SET ENCODED=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:NAME)"') DO SET "ENCODED=%%E"
SET RESPONSE_FILE=%TEMP%\zone_%RANDOM%.json
SET UNITS_FILE=%TEMP%\zone_units_%RANDOM%.json

SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%ENCODED%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %NAME% ^(HTTP %HTTP_CODE%^):
    TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
TYPE "%RESPONSE_FILE%"
echo.
echo.
echo In short:
powershell -NoProfile -Command "$z = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0}, default {1}, {2} edge(s)' -f $z.name, ([string]$z.isDefault).ToLower(), ($z.edges | Measure-Object).Count; foreach ($e in @($z.edges)) { if ($e) { '  edge {0}: {1} protocol(s), {2} prox(ies), {3} address(es)' -f $e.title, ($e.protocols | Measure-Object).Count, ($e.proxies | Measure-Object).Count, ($e.ipAddresses | Measure-Object).Count } }"
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/businessUnits" ^
  --data-urlencode "fields=name,dmz" --data-urlencode "limit=1000" -H "accept: application/json" -H "%REFERER_HEADER%" > "%UNITS_FILE%"
powershell -NoProfile -Command "$u = @((Get-Content -Raw $env:UNITS_FILE | ConvertFrom-Json).result | Where-Object { $_.dmz -ceq $env:NAME } | ForEach-Object { $_.name }); '  business units that name it: ' + $(if ($u.Count) { $u -join ', ' } else { 'none' })"

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%UNITS_FILE%" DEL "%UNITS_FILE%"
