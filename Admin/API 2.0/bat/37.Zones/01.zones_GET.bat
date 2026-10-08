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
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200, 1 otherwise, 2 when there is more than one argument (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\zones_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/zones
SET NAME=%~1
IF NOT "%~2"=="" GOTO usage
SET SHOWN=%NAME%
IF "%SHOWN%"=="" SET "SHOWN=(any)"
SET NAME_FILTER=
IF NOT "%NAME%"=="" SET NAME_FILTER=--data-urlencode "name=%NAME%"

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%?limit=1&fields=name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
FOR /F %%N IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).resultSet.totalCount"') DO echo Zones on the server: %%N

echo.
echo The zones named %SHOWN%: name, default, edges, description:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G %NAME_FILTER% --data-urlencode "limit=0"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($z in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($z -and ($env:NAME -eq '' -or $z.name -ceq $env:NAME)) { '  {0}  default {1}  edges {2}  {3}' -f $z.name, ([string]$z.isDefault).ToLower(), ($z.edges | Measure-Object).Count, $(if ($z.description) { $z.description } else { '-' }) } }"

echo.
echo The default zone:
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "isDefault=true" --data-urlencode "limit=0"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "foreach ($z in @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result)) { if ($z -and $z.isDefault) { '  {0}  default {1}  edges {2}  {3}' -f $z.name, ([string]$z.isDefault).ToLower(), ($z.edges | Measure-Object).Count, $(if ($z.description) { $z.description } else { '-' }) } }"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 01.zones_GET.bat [NAME]
EXIT /B 2
