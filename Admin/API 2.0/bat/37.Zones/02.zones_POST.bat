@echo off
REM ==============================================================================
REM Script Name: 02.zones_POST.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script creates a network zone using the `/zones` endpoint.
REM It demonstrates:
REM - A zone with a name and a description, and no edge
REM - Optionally one edge: a title, an address and one SSH protocol with a port (left disabled)
REM - Reading the new zone's address from the Location header
REM
REM Usage:
REM 02.zones_POST.bat [NAME [DESCRIPTION [EDGE_TITLE [EDGE_ADDRESS [EDGE_PORT]]]]]
REM
REM   NAME          the zone's name (default example_zone); not \ / ; ' , at most 255 characters
REM   DESCRIPTION   its description (default "Created by the examples"), at most 255 characters
REM   EDGE_TITLE    add one edge with this title (same characters rules as NAME)
REM   EDGE_ADDRESS  the edge's address, a host name or an address (needs EDGE_TITLE)
REM   EDGE_PORT     an SSH protocol on this port, 1024 to 65535, left disabled (needs EDGE_TITLE)
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - A zone is a NETWORK ZONE (a DMZ zone): it describes where the server's protocol servers are reached from. The lab has one,
REM   `Private` ("This network zone holds the information for back ends", one edge `Host` with the lab's own FTP, SSH, HTTP, ADMIN,
REM   AS2 and PESIT ports); a DMZ zone lists its edge servers in `edges` (title, addresses, protocols with ports, proxies). A zone is
REM   addressed by its NAME in the path, and the name is case sensitive (`Private` is found, `private` is a 404). Never change or
REM   delete `Private`: the examples default to an `example_*` zone, and the ones that change something need the name.
REM - Run 07.zones_name_DELETE.bat to remove what this creates. A zone that only describes an edge changes nothing by itself: no
REM   listener is opened and no traffic is routed until a business unit names it (see 04.zones_name_GET.bat). `isDefault` is not sent, so the zone
REM   is not the default (a default zone is one the server applies when a new object names none; see 05 and 06).
REM - Confirmed directly: a success is 201 with the zone's address in `Location` and no body. Only `name` is required (`{}` is 400 "name must not be
REM   null"). A duplicate is **400** "The zone name is not unique.", not the 409 the reference lists, and names are case sensitive (`example_a`
REM   and `EXAMPLE_A` coexist). A name with `/`, `\`, `;` or `'` is 400, one of 256 characters is 400 "name length must be between 1 and 255 characters"; a
REM   space, an accent and a dash are accepted (the Location then holds the name URL-encoded). An unknown field is 400 "Unsupported parameter - bogus".
REM   An edge needs a `title` (400 "edges[0].title must not be null"; the same characters as a name); its `deploymentSite` defaults to `Prod`, `enabledProxy`
REM   and a protocol's `isEnabled` to false, and the edge gets an `edgeId`. A protocol needs `streamingProtocol` (HTTP, FTP, AS2, SSH, PESIT or ADMIN; another
REM   value is 403 "unable to comply") and a `port` from 1024 (400 "Port number for protocol HTTP must be from 1024 to 65535"). A protocol's `sslAlias` that is not a
REM   certificate of the server is 400 "Error creating zone". The protocols come back in the server's order, not the one sent. A proxy
REM   (`proxyProtocol` SOCKS_PROXY or HTTP_PROXY, `port`, `username`, `isUsePassword`, `password`) is accepted and its password is never read back (`null`).
REM   Left out of this script on purpose: more than one edge, the proxies and the extra fields; send them in a body of your own.
REM - PowerShell is used to build the request body, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_zone
SET DESCRIPTION=%~2
IF "%DESCRIPTION%"=="" SET "DESCRIPTION=Created by the examples"
SET EDGE_TITLE=%~3
SET EDGE_ADDRESS=%~4
SET EDGE_PORT=%~5
powershell -NoProfile -Command "if ($env:NAME.Length -eq 0 -or $env:NAME.Length -gt 255 -or $env:NAME -match '[/\;'']') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo NAME must be 1 to 255 characters, none of \ / ; ' .
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:DESCRIPTION.Length -gt 255) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo DESCRIPTION is 255 characters at most.
    EXIT /B 2
)
IF "%EDGE_TITLE%"=="" (
    IF NOT "%EDGE_ADDRESS%%EDGE_PORT%"=="" (
        echo EDGE_ADDRESS and EDGE_PORT need an EDGE_TITLE.
        EXIT /B 2
    )
)
IF NOT "%EDGE_TITLE%"=="" (
    powershell -NoProfile -Command "if ($env:EDGE_TITLE.Length -gt 255 -or $env:EDGE_TITLE -match '[/\;'']') { exit 1 } else { exit 0 }"
    IF ERRORLEVEL 1 (
        echo EDGE_TITLE must be 1 to 255 characters, none of \ / ; ' .
        EXIT /B 2
    )
)
IF NOT "%EDGE_PORT%"=="" (
    powershell -NoProfile -Command "if ($env:EDGE_PORT -match '^[0-9]+$' -and [int64]$env:EDGE_PORT -ge 1024 -and [int64]$env:EDGE_PORT -le 65535) { exit 0 } else { exit 1 }"
    IF ERRORLEVEL 1 (
        echo EDGE_PORT is a number from 1024 to 65535, not %EDGE_PORT%.
        EXIT /B 2
    )
)
SET BODY_FILE=%TEMP%\zone_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\zone_response_%RANDOM%.txt
SET HEADERS_FILE=%TEMP%\zone_headers_%RANDOM%.txt

powershell -NoProfile -Command "$b = [ordered]@{ name = $env:NAME; description = $env:DESCRIPTION }; if ($env:EDGE_TITLE) { $e = [ordered]@{ title = $env:EDGE_TITLE }; if ($env:EDGE_ADDRESS) { $e.ipAddresses = @(@{ ipAddress = $env:EDGE_ADDRESS }) }; if ($env:EDGE_PORT) { $e.protocols = @(@{ streamingProtocol = 'SSH'; port = [int]$env:EDGE_PORT; isEnabled = $false }) }; $b.edges = @($e) }; [IO.File]::WriteAllText($env:BODY_FILE, ($b | ConvertTo-Json -Compress -Depth 10))"

echo Creating the zone %NAME%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -D "%HEADERS_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="201" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } else { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
    EXIT /B 1
)
FOR /F "tokens=1,* delims=: " %%A IN ('findstr /B /I "location:" "%HEADERS_FILE%"') DO echo It is at %%B
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF EXIST "%HEADERS_FILE%" DEL "%HEADERS_FILE%"
