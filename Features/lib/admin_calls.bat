@echo off
REM ==============================================================================
REM Script Name: admin_calls.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM The other Admin API calls the features need besides a POST (post_admin.bat),
REM shared across Features/.
REM
REM Usage:
REM CALL admin_calls.bat delete PATH
REM CALL admin_calls.bat exists PATH
REM CALL admin_calls.bat encode PATH
REM
REM   delete   DELETE PATH on the Admin API and print the response and the HTTP code.
REM            ERRORLEVEL is 0 only for a 2xx code.
REM   exists   HEAD PATH and print nothing. ERRORLEVEL is 0 when it answers 200, 1
REM            when it answers 404, 2 for anything else (the server did not answer,
REM            or refused): then nobody knows, and a clean-up must not say "nothing
REM            to delete".
REM   encode   sets AC_ENCODED_PATH to PATH with each segment URL-encoded (a space or
REM            a # in a name must not end the path early); the / between the segments
REM            stays. enduser.bat uses it too.
REM
REM delete and exists set AR_ADMIN_CODE to the HTTP code of the call (000 when there
REM was no answer at all). PATH is encoded by segment, like in enduser.bat.
REM
REM Notes:
REM - Needs ST_SERVER, ST_PORT, ST_USER and ST_PASSWORD.
REM - Uses PowerShell to encode the path.
REM ==============================================================================

GOTO :%~1

:delete
CALL :encode "%~2"
SET AC_HEADERS=%TEMP%\ar_ac_headers_%RANDOM%.txt
SET AR_ADMIN_CODE=
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "https://%ST_SERVER%:%ST_PORT%/api/v2.0/%AC_ENCODED_PATH%" ^
  -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -D "%AC_HEADERS%"
FOR /F "tokens=2" %%C IN ('findstr /B /I "HTTP/" "%AC_HEADERS%"') DO SET AR_ADMIN_CODE=%%C
IF EXIST "%AC_HEADERS%" DEL "%AC_HEADERS%"
IF NOT DEFINED AR_ADMIN_CODE SET AR_ADMIN_CODE=000
echo.
echo HTTP %AR_ADMIN_CODE%
IF "%AR_ADMIN_CODE:~0,1%"=="2" EXIT /B 0
EXIT /B 1

:exists
CALL :encode "%~2"
SET AR_ADMIN_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" --head "https://%ST_SERVER%:%ST_PORT%/api/v2.0/%AC_ENCODED_PATH%" -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT"') DO SET AR_ADMIN_CODE=%%C
IF NOT DEFINED AR_ADMIN_CODE SET AR_ADMIN_CODE=000
IF "%AR_ADMIN_CODE%"=="200" EXIT /B 0
IF "%AR_ADMIN_CODE%"=="404" EXIT /B 1
EXIT /B 2

:encode
SET "AC_RAW_PATH=%~1"
SET AC_ENCODED_PATH=
FOR /F "usebackq delims=" %%E IN (`powershell -NoProfile -Command "($env:AC_RAW_PATH -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'"`) DO SET AC_ENCODED_PATH=%%E
IF NOT DEFINED AC_ENCODED_PATH SET AC_ENCODED_PATH=%AC_RAW_PATH%
EXIT /B 0
