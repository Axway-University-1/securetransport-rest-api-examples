@echo off
REM ==============================================================================
REM Script Name: 02.configurations_PATCH_UsageReporting.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script configures the automatic usage reporting to the Axway Platform, by patching the ten
REM StatisticsSummaryReport Server Configuration Options, using the `/configurations/options/{name}` endpoint.
REM It demonstrates:
REM - Every value taken from an environment variable: the client secret is never in the file, and a value that is missing, or still
REM   a placeholder such as <PUT YOUR CLIENT ID HERE>, stops the script before anything is sent
REM - The old values of all ten options read and printed first, so that they can be put back
REM - Request bodies built with jq, and an exit at the first option the server refuses
REM
REM Usage:
REM SET ST_USAGE_CLIENT_ID=...
REM SET ST_USAGE_CLIENT_SECRET=...
REM SET ST_USAGE_ENVIRONMENT_ID=...
REM SET ST_USAGE_ENVIRONMENT_NAME=...
REM SET ST_USAGE_FILE_PATH=/a/folder/on/the/server
REM SET ST_USAGE_PLATFORM_API=https://...
REM SET ST_USAGE_PLATFORM_AUTHENTICATION=https://...
REM SET ST_USAGE_SCHEMA_ID=https://...
REM SET ST_USAGE_DAYS_TO_INCLUDE=3
REM SET ST_USAGE_NETWORK_ZONE=...      (optional)
REM 02.configurations_PATCH_UsageReporting.bat
REM
REM   The client, secret and environment are the ones of the Axway Platform (https://platform.axway.com/). ST_USAGE_FILE_PATH is a folder on the server where the
REM   reports are written. The platform addresses are the ones the server has by default in newer versions. ST_USAGE_NETWORK_ZONE is the edge the connection to the
REM   platform must pass through: when it is not set, the option is set to empty. Without the nine others, or with one that is still a placeholder, the script
REM   prints what is missing, sends NOTHING and exits 2.
REM
REM Risk: config - writes ten server wide options, among them a client secret; the script prints the old values first
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This writes ten server wide options, among them a client secret. The secret is read from the environment only, so it is in no file and no argument, and the script never prints it.
REM   (The old value of the secret is printed as the server keeps it, encrypted: `{AES128}...`.)
REM - The old values of the ten options are read first (an option that cannot be read stops the script before any change) and printed as `option: [values]`. To put them back, set the
REM   variables to them and run the script again: the encrypted secret is accepted as it is, and the server keeps it unchanged.
REM - PowerShell is used to read the old values and build each request body, in place of jq.
REM - Each option is patched with `replace` of `/values`. The script stops at the first answer that is not 2xx and says which options were changed already.
REM - Confirmed directly: each PATCH answers 204 with no body. The options read `readOnly` true and are patched anyway. An option sent the already encrypted text of its own secret reads back unchanged;
REM   a plain value sent to ClientSecret is stored encrypted, and the encrypted text differs on every write. The server checks no value against its meaning ("abc" was accepted for the number of days),
REM   so the script checks the days and the two addresses itself. An option is cleared with `[""]`.
REM - NOT run against the Amplify Platform: only against the lab's own options, which were put back (check 21). With AutomaticReport on, the server sends a report with these settings.
REM - Exit codes: 0 when every option was set, 1 when an option cannot be read or the server refuses one, 2 when a variable is missing or still a placeholder (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/configurations/options
SET SCO=StatisticsSummaryReport
SET PROBLEMS=

REM Nothing is sent until every value is there and none is a placeholder.
CALL :need ST_USAGE_CLIENT_ID yes
CALL :need ST_USAGE_CLIENT_SECRET yes
CALL :need ST_USAGE_ENVIRONMENT_ID yes
CALL :need ST_USAGE_ENVIRONMENT_NAME yes
CALL :need ST_USAGE_FILE_PATH yes
CALL :need ST_USAGE_NETWORK_ZONE no
CALL :need ST_USAGE_PLATFORM_API yes
CALL :need ST_USAGE_PLATFORM_AUTHENTICATION yes
CALL :need ST_USAGE_SCHEMA_ID yes
CALL :need ST_USAGE_DAYS_TO_INCLUDE yes
IF DEFINED ST_USAGE_DAYS_TO_INCLUDE (
    powershell -NoProfile -Command "if ($env:ST_USAGE_DAYS_TO_INCLUDE -match '^[0-9]{1,4}$') { exit 0 } else { exit 1 }"
    IF ERRORLEVEL 1 (
        echo ST_USAGE_DAYS_TO_INCLUDE is a whole number of days.
        SET PROBLEMS=1
    )
)
CALL :need_https ST_USAGE_PLATFORM_API
CALL :need_https ST_USAGE_PLATFORM_AUTHENTICATION
IF DEFINED PROBLEMS (
    echo Nothing was sent. Set the variables listed above ^(see the usage in the header of this script^) and run it again.
    EXIT /B 2
)

SET RESPONSE_FILE=%TEMP%\usage_response_%RANDOM%.json
SET BODY_FILE=%TEMP%\usage_body_%RANDOM%.json

echo Reading the old values of the ten options...
CALL :read_old "%SCO%.ClientId"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.ClientSecret"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.EnvironmentId"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.EnvironmentName"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.FilePath"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.NetworkZone"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.Platform.API"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.Platform.Authentication"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.SchemaId"
IF ERRORLEVEL 1 EXIT /B 1
CALL :read_old "%SCO%.AutomaticReport.DaysToInclude"
IF ERRORLEVEL 1 EXIT /B 1

SET CHANGED=
CALL :patch_option "%SCO%.ClientId" ST_USAGE_CLIENT_ID shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.ClientSecret" ST_USAGE_CLIENT_SECRET hidden
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.EnvironmentId" ST_USAGE_ENVIRONMENT_ID shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.EnvironmentName" ST_USAGE_ENVIRONMENT_NAME shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.FilePath" ST_USAGE_FILE_PATH shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.NetworkZone" ST_USAGE_NETWORK_ZONE shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.Platform.API" ST_USAGE_PLATFORM_API shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.Platform.Authentication" ST_USAGE_PLATFORM_AUTHENTICATION shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.SchemaId" ST_USAGE_SCHEMA_ID shown
IF ERRORLEVEL 1 EXIT /B 1
CALL :patch_option "%SCO%.AutomaticReport.DaysToInclude" ST_USAGE_DAYS_TO_INCLUDE shown
IF ERRORLEVEL 1 EXIT /B 1

echo Done: 10 options set. The old values are listed above.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Checks the variable named in %1: set (unless %2 is no) and not a placeholder
REM ------------------------------------------------------------------------------
:need
SET NEED_NAME=%~1
IF NOT DEFINED %NEED_NAME% (
    IF "%~2"=="yes" (
        echo %NEED_NAME% is not set.
        SET PROBLEMS=1
    )
    EXIT /B 0
)
powershell -NoProfile -Command "$v = [Environment]::GetEnvironmentVariable($env:NEED_NAME); if ($v -match '^<.*>$' -or $v -match 'PUT YOUR') { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo %NEED_NAME% still holds a placeholder.
    SET PROBLEMS=1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Checks that the variable named in %1, when set, is an https address
REM ------------------------------------------------------------------------------
:need_https
SET NEED_NAME=%~1
IF NOT DEFINED %NEED_NAME% EXIT /B 0
powershell -NoProfile -Command "if ([Environment]::GetEnvironmentVariable($env:NEED_NAME) -like 'https://*') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo %NEED_NAME% is an https address.
    SET PROBLEMS=1
)
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Reads and prints the values of the option named in %1; exit 1 when it cannot be read
REM ------------------------------------------------------------------------------
:read_old
SET OPTION=%~1
SET OPTION_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:OPTION)"') DO SET OPTION_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%/%OPTION_URI%" --data-urlencode "fields=values" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not read %OPTION%: HTTP %HTTP_CODE%. Nothing was changed.
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  {0}: {1}' -f $env:OPTION, (ConvertTo-Json -InputObject @($r.values | Where-Object { $_ -ne $null }) -Compress)"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Patches the option named in %1 with the value of the variable named in %2; %3 is hidden for a secret
REM ------------------------------------------------------------------------------
:patch_option
SET OPTION=%~1
SET VALUE_VARIABLE=%~2
SET OPTION_URI=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:OPTION)"') DO SET OPTION_URI=%%E
powershell -NoProfile -Command "$v = [string][Environment]::GetEnvironmentVariable($env:VALUE_VARIABLE); $op = [ordered]@{ op = 'replace'; path = '/values'; value = @($v) }; [IO.File]::WriteAllText($env:BODY_FILE, (ConvertTo-Json -InputObject @($op) -Compress -Depth 5))"
IF "%~3"=="hidden" (
    echo Updating %OPTION% to '^(hidden^)'...
) ELSE (
    powershell -NoProfile -Command "'Updating ' + $env:OPTION + ' to ' + [char]39 + [Environment]::GetEnvironmentVariable($env:VALUE_VARIABLE) + [char]39 + '...'"
)
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%OPTION_URI%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
SET IS_OK=
IF "%HTTP_CODE:~0,1%"=="2" SET IS_OK=yes
IF NOT "%IS_OK%"=="yes" (
    powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
    IF DEFINED CHANGED echo Already changed:%CHANGED%
    echo Stopped at %OPTION%. The old values are listed above.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
SET CHANGED=%CHANGED% %OPTION%
EXIT /B 0
