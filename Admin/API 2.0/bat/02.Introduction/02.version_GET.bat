@echo off
REM ==============================================================================
REM Script Name: 02.version_GET.bat
REM Author: Plamen Milenkov
REM Created: 2025-08-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script performs a basic authentication request to retrieve the current
REM product version from the API. It stores the full response in a variable and
REM filters specific fields such as version, server type, and operating system.
REM
REM Usage:
REM 02.version_GET.bat
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This script demonstrates how to parse and filter JSON responses using findstr.
REM - 01.version_GET.bat makes the same call and prints the whole answer; this one keeps it in a variable and picks lines out.
REM - The findstr calls only show what is in the answer. findstr exits 1 when it finds nothing (a server that is not 5.5 has no line for
REM   "version.*5.5"), so the script no longer ends with the status of the last findstr: its exit code is that of the call.
REM - Confirmed directly: on a 5.5-20260924 server `findstr "version"` finds the release and the versions of the components
REM   the answer lists, `findstr "os"` finds both "os" and "osDistribution", and 401 ("Authentication required.",
REM   plain text) is the answer to refused credentials: the script prints the status and that text and exits 1.
REM - Exit codes: 0 when the answer is 200 (whatever the findstr calls find), 1 otherwise.
REM ==============================================================================

SETLOCAL

echo Loading variables into our context...
CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\version_response_%RANDOM%.json

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
REM Store full response in a temporary file
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "https://%ST_SERVER%:%ST_PORT%/api/v2.0/version" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    CALL :show_failure
    EXIT /B 1
)

REM Uncomment to see full response
REM type "%RESPONSE_FILE%"

REM Extract version
echo.
echo grep for the version...
findstr "version" "%RESPONSE_FILE%"

REM Filter specific SPI version
echo.
echo grep for version.*5.5...
findstr "version.*5.5" "%RESPONSE_FILE%"

REM Extract server type
echo.
echo grep for serverType...
findstr "serverType" "%RESPONSE_FILE%"

REM Extract operating system
echo.
echo grep for os...
findstr "os" "%RESPONSE_FILE%"

REM The findstr calls above only show lines: the exit code is that of the call, which answered 200
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A status other than the one expected: print it and the server's answer
REM ------------------------------------------------------------------------------
:show_failure
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1
