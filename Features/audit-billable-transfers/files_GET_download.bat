@echo off
REM ==============================================================================
REM Script Name: files_GET_download.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-02
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Downloads one file from the test account's home folder, as a client would,
REM COUNT times in a row, using the End User API `GET /files/{path}` endpoint. It
REM logs in once as the account, downloads, and logs out.
REM
REM Each download is a transfer of its own. Run billable_GET_report.bat before and
REM after to see how much repeated client downloads add to the usage reporting.
REM
REM Not numbered, so 00.run_all.bat does not run it: it is a separate experiment,
REM run by hand against a file that is already in the account's home folder.
REM
REM Usage:
REM files_GET_download.bat FILE [COUNT [ACCOUNT]]
REM
REM   FILE     the file to download, relative to the account's home folder, for
REM            example subscription/s1/only_inbound.txt, where scenario 2.1 lands in
REM            the test account, or btTestAccount/delivered-1/inbound_and_one_outbound.txt
REM            as partner_to_push_to
REM   COUNT    how many times to download it (default 1)
REM   ACCOUNT  the account to log in as: the test account (default btTestAccount)
REM            or a partner. Its password is BT_ACCOUNT_PASSWORD, the one
REM            00.run_all.bat creates all three accounts with.
REM
REM For example:
REM files_GET_download.bat subscription/s1/only_inbound.txt 50
REM files_GET_download.bat btTestAccount/delivered-1/inbound_and_one_outbound.txt 50 partner_to_push_to
REM
REM Notes:
REM - Needs settings.local.bat with BT_ACCOUNT_PASSWORD. See settings.bat.
REM - Uses PowerShell to URL-encode the path.
REM - The downloaded content is discarded; only the HTTP code of each download is
REM   kept. Exits 1 if any download did not answer 200.
REM - The port is BT_ENDUSER_PORT, 8443 by default. It is not the Admin port.
REM ==============================================================================

SETLOCAL

IF "%~1"=="" GOTO :usage
IF NOT "%~4"=="" GOTO :usage
SET FILE_ARG=%~1
SET COUNT=%~2
IF "%COUNT%"=="" SET COUNT=1
ECHO %COUNT%| FINDSTR /R /X "[1-9][0-9]*" >NUL || (
    echo COUNT must be a whole number, 1 or more: %COUNT%
    EXIT /B 2
)
IF NOT "%~3"=="" (
    ECHO %~3| FINDSTR /R /X "[A-Za-z0-9._-]*" >NUL || (
        echo ACCOUNT may use only letters, digits, '.', '_' and '-': %~3
        EXIT /B 2
    )
    SET BT_RUN_ACCOUNT=%~3
)

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

IF "%BT_ACCOUNT_PASSWORD%"=="" (
    echo BT_ACCOUNT_PASSWORD is not set. Copy settings.local.example.bat to settings.local.bat and choose one.
    EXIT /B 1
)

REM Relative to the home folder, so a leading / is dropped. Each segment of the
REM path is URL-encoded on its own, so a space or a # in a name survives, and the
REM / between the segments stays a /
IF "%FILE_ARG:~0,1%"=="/" SET FILE_ARG=%FILE_ARG:~1%
SET FILE_PATH=%FILE_ARG%
SET ENCODED_PATH=
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "($env:FILE_PATH -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'"') DO SET ENCODED_PATH=%%E

CALL "%~dp0..\lib\enduser.bat" login
IF ERRORLEVEL 1 EXIT /B 1

echo Downloading %FILE_PATH% from %BT_TEST_ACCOUNT%'s home folder, %COUNT% time^(s^)...
SET OK=0
SET FAILED_CODES=
FOR /L %%I IN (1,1,%COUNT%) DO CALL :download_one %%I

CALL "%~dp0..\lib\enduser.bat" logout

echo %OK% of %COUNT% download^(s^) succeeded.
IF NOT "%OK%"=="%COUNT%" (
    echo Failed ^(download:HTTP code^):%FAILED_CODES%
    EXIT /B 1
)
EXIT /B 0

:download_one
SET DL_CODE=
FOR /F %%C IN ('curl -L -s -k -b "%EU_JAR%" -X GET "https://%ST_SERVER%:%EU_ENDUSER_PORT%/api/v2.0/files/%ENCODED_PATH%" -H "accept: */*" -H "Referer: THIS_IS_A_RANDOM_TEXT" -H "csrfToken: %EU_CSRF%" -o NUL -w "%%{http_code}"') DO SET DL_CODE=%%C
IF "%DL_CODE%"=="200" (
    SET /A OK=%OK%+1
) ELSE (
    SET FAILED_CODES=%FAILED_CODES% %1:%DL_CODE%
)
echo   %1 of %COUNT%: HTTP %DL_CODE%
EXIT /B 0

:usage
echo Usage: files_GET_download.bat FILE [COUNT [ACCOUNT]]
EXIT /B 2
