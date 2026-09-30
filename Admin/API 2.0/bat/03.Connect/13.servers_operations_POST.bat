@echo off
REM ==============================================================================
REM Script Name: 13.servers_operations_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script manages server operations using the `/servers/operations` endpoint.
REM It demonstrates:
REM - Starting servers that are currently stopped
REM - Starting daemons required for server activation
REM
REM Usage:
REM 13.servers_operations_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Daemons must be running for certain servers to start successfully.
REM - Delayed expansion is enabled because the loops below read variables that
REM   are set inside the same block. Those are referenced as !VAR! and not %VAR%,
REM   which would be expanded once when the block is parsed.
REM ==============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

echo Getting the list of servers...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers?fields=serverName,isActive" ^
-H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" > servers.json

FOR /F %%i IN ('powershell -Command "(Get-Content servers.json | ConvertFrom-Json).result.Count"') DO SET NUMBER_OF_SERVERS=%%i
echo Found %NUMBER_OF_SERVERS% servers

REM The results are indexed from zero, so the last index is one less than the count
SET /A LAST_SERVER=%NUMBER_OF_SERVERS%-1

FOR /L %%i IN (0,1,%LAST_SERVER%) DO (
    FOR /F "tokens=*" %%A IN ('powershell -Command "(Get-Content servers.json | ConvertFrom-Json).result[%%i].serverName"') DO SET NAME=%%A
    FOR /F "tokens=*" %%B IN ('powershell -Command "(Get-Content servers.json | ConvertFrom-Json).result[%%i].isActive"') DO SET IS_ACTIVE=%%B
    IF "!IS_ACTIVE!"=="True" (
        echo Server: !NAME! is running
    ) ELSE (
        echo Server: !NAME! is not running
        echo Starting server !NAME!...
        curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/servers/operations?serverName=!NAME!&operation=start" ^
        -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"
    )
)

echo Getting the list of daemons...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons" ^
-H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" > daemons.json

FOR %%D IN (ssh,as2,pesit,ftp,http) DO (
    FOR /F "tokens=*" %%S IN ('powershell -Command "(Get-Content daemons.json | ConvertFrom-Json).%%DStatus"') DO SET STATUS=%%S
    IF "!STATUS!"=="Not running" (
        echo Starting daemon %%D...
        curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/daemons/operations?operation=start&daemon=%%D" ^
        -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json"
    ) ELSE (
        echo Daemon %%D is running
    )
)

REM Remove the temporary API responses
IF EXIST servers.json DEL servers.json
IF EXIST daemons.json DEL daemons.json

ENDLOCAL
