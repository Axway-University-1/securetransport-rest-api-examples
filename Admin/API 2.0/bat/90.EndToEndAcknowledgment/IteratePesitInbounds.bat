@echo off
REM ==============================================================================
REM Script Name: IteratePesitInbounds.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script automates the retrieval and processing of PeSIT inbound transfers.
REM It identifies transfers within a time window that have not yet received an
REM acknowledgment, and triggers Acknowledgment.bat for each one.
REM
REM Key Features:
REM - Builds the time window with PowerShell, in the RFC 2822 format the API wants
REM - URL encodes the timestamps
REM - Logs all operations with timestamps
REM - Optionally clears API output files after processing
REM
REM Usage:
REM IteratePesitInbounds.bat START_HOURS_AGO END_HOURS_AGO [HOST] [ROOT_FOLDER] [CLEAR_API_OUTPUT_FILES]
REM
REM Parameters:
REM START_HOURS_AGO         - Number of hours ago to start the time window.
REM END_HOURS_AGO           - Number of hours ago to end the time window.
REM HOST                    - API host (defaults to ST_SERVER, then localhost).
REM ROOT_FOLDER             - Root directory for logs and outputs (default: C:\Temp).
REM CLEAR_API_OUTPUT_FILES  - TRUE to delete API output files after processing.
REM
REM Dependencies:
REM - curl
REM - PowerShell, used to read JSON in place of jq
REM
REM Exit Codes:
REM 0 - Success
REM 1 - Error (e.g. missing parameters, API failure)
REM
REM Risk: write
REM
REM Notes:
REM - Credentials come from set_variables.bat, which loads set_variables.local.bat.
REM ==============================================================================

SETLOCAL ENABLEDELAYEDEXPANSION

REM
REM Load the connection details and credentials. Put your own values in
REM set_variables.local.bat so that they stay out of the repository.
REM
CALL "%~dp0..\set_variables.bat"

REM Exit codes
SET EXIT_CODE_SUCCESS=0
SET EXIT_CODE_ERROR=1

REM Parse Input Parameters
SET START_HOURS_AGO=%1
SET END_HOURS_AGO=%2

SET HOST=%3
IF "%HOST%"=="" SET HOST=%ST_SERVER%
IF "%HOST%"=="" SET HOST=localhost

SET ROOT_FOLDER=%4
IF "%ROOT_FOLDER%"=="" SET ROOT_FOLDER=C:\Temp

SET CLEAR_API_OUTPUT_FILES=%5
IF "%CLEAR_API_OUTPUT_FILES%"=="" SET CLEAR_API_OUTPUT_FILES=FALSE

IF "%START_HOURS_AGO%"=="" GOTO :usage
IF "%END_HOURS_AGO%"=="" GOTO :usage
GOTO :parameters_ok

:usage
echo Usage: %~nx0 START_HOURS_AGO END_HOURS_AGO [HOST] [ROOT_FOLDER] [CLEAR_API_OUTPUT_FILES]
EXIT /B %EXIT_CODE_ERROR%

:parameters_ok

IF "%ST_PORT%"=="" SET ST_PORT=444
SET API_URL=https://%HOST%:%ST_PORT%/api/v2.0
SET ADMIN_USER=%ST_USER%
SET ADMIN_PWD=%ST_PASSWORD%

IF "%ADMIN_USER%"=="" GOTO :no_credentials
IF "%ADMIN_PWD%"=="" GOTO :no_credentials
GOTO :credentials_ok

:no_credentials
echo No credentials found. Set ST_USER and ST_PASSWORD in set_variables.local.bat next to set_variables.bat.
EXIT /B %EXIT_CODE_ERROR%

:credentials_ok

REM Set script variables
FOR /F "tokens=1-2 delims= " %%A IN ('powershell -Command "Get-Date -Format yyyyMMdd HHmm"') DO (
    SET YYYYMMDD=%%A
    SET HH=%%B
)

SET MAIN_DIR=%ROOT_FOLDER%\acks
SET LOG_DIR=%MAIN_DIR%\%YYYYMMDD%-%HH%
SET API_OUTPUTS_DIR=%LOG_DIR%\API
SET FILELOG=%LOG_DIR%\All_PeSIT_Inbound_%START_HOURS_AGO%_%END_HOURS_AGO%.log

REM Create necessary directories
IF NOT EXIST "%API_OUTPUTS_DIR%" mkdir "%API_OUTPUTS_DIR%"
echo All log files will be saved in: %LOG_DIR%

CALL :log_message INFO "##############################################################"
CALL :log_message INFO "Starting script execution..."

REM --- Find all transfers ---
CALL :log_message INFO "Looking for all PeSIT inbound transfers..."
SET ALL_PESIT_INBOUND=%API_OUTPUTS_DIR%\ALL_PESIT_INBOUND.txt

REM
REM Build the time window. The API expects RFC 2822, URL encoded.
REM PowerShell does both, so there is no need for a hand written encoder.
REM
FOR /F "tokens=*" %%S IN ('powershell -Command "[System.Web.HttpUtility]::UrlEncode((Get-Date).ToUniversalTime().AddHours(-%START_HOURS_AGO%).ToString('ddd, dd MMM yyyy HH:mm:ss +0000', [Globalization.CultureInfo]::InvariantCulture))" 2^>nul') DO SET START_TIME_ENCODED=%%S
FOR /F "tokens=*" %%E IN ('powershell -Command "[System.Web.HttpUtility]::UrlEncode((Get-Date).ToUniversalTime().AddHours(-%END_HOURS_AGO%).ToString('ddd, dd MMM yyyy HH:mm:ss +0000', [Globalization.CultureInfo]::InvariantCulture))" 2^>nul') DO SET END_TIME_ENCODED=%%E

IF "%START_TIME_ENCODED%"=="" (
    REM System.Web is not loaded by default on every PowerShell version. Fall back to Uri.
    FOR /F "tokens=*" %%S IN ('powershell -Command "[System.Uri]::EscapeDataString((Get-Date).ToUniversalTime().AddHours(-%START_HOURS_AGO%).ToString('ddd, dd MMM yyyy HH:mm:ss +0000', [Globalization.CultureInfo]::InvariantCulture))"') DO SET START_TIME_ENCODED=%%S
    FOR /F "tokens=*" %%E IN ('powershell -Command "[System.Uri]::EscapeDataString((Get-Date).ToUniversalTime().AddHours(-%END_HOURS_AGO%).ToString('ddd, dd MMM yyyy HH:mm:ss +0000', [Globalization.CultureInfo]::InvariantCulture))"') DO SET END_TIME_ENCODED=%%E
)

CALL :log_message INFO "Start time (%START_HOURS_AGO% hours ago), encoded: %START_TIME_ENCODED%"
CALL :log_message INFO "End time (%END_HOURS_AGO% hours ago), encoded: %END_TIME_ENCODED%"

CALL :execute_API GET "%API_URL%/logs/transfers?protocol=pesit&direction=Incoming&status=Processed&endTimeAfter=%START_TIME_ENCODED%&endTimeBefore=%END_TIME_ENCODED%&fields=coreId,pesitAckStatus" "%ALL_PESIT_INBOUND%"

REM
REM Select the transfers that have no acknowledgment status yet, and collect
REM their Core IDs. This is the PowerShell equivalent of the jq select used by
REM the bash version.
REM
SET CORE_ID_LIST=%API_OUTPUTS_DIR%\CORE_IDS.txt
powershell -Command "(Get-Content '%ALL_PESIT_INBOUND%' -Raw | ConvertFrom-Json).result | Where-Object { $null -eq $_.pesitAckStatus } | ForEach-Object { $_.coreId } | Set-Content '%CORE_ID_LIST%'"

SET /A FOUND=0
FOR /F "usebackq tokens=*" %%C IN ("%CORE_ID_LIST%") DO SET /A FOUND+=1
CALL :log_message INFO "Found %FOUND% PeSIT inbound transfers."

FOR /F "usebackq tokens=*" %%C IN ("%CORE_ID_LIST%") DO (
    CALL :log_message INFO "Processing Core ID: %%C"
    REM Call the Acknowledgment script for each Core ID
    CALL "%~dp0Acknowledgment.bat" %%C "%HOST%" MIX 1 FALSE "%ROOT_FOLDER%"
)

IF /I "%CLEAR_API_OUTPUT_FILES%"=="TRUE" (
    CALL :log_message INFO "Clearing API output files in directory: %API_OUTPUTS_DIR%"
    DEL /Q "%API_OUTPUTS_DIR%\*.txt"
)

CALL :log_message INFO "End of script execution"
EXIT /B %EXIT_CODE_SUCCESS%

REM --- Functions ---
:log_message
SET level=%1
SET msg=%2
FOR /F "tokens=*" %%A IN ('powershell -Command "Get-Date -Format ''yyyy-MM-dd HH:mm:ss''"') DO SET timestamp=%%A
echo %timestamp% - %level% - %msg% >> "%FILELOG%"
EXIT /B

:execute_API
SET method=%1
SET url=%2
SET output_file=%3
FOR /F %%H IN ('curl -k -s -o "%output_file:"=%" -w "%%{http_code}" -u "%ADMIN_USER%:%ADMIN_PWD%" -X %method% "%url:"=%" -H "accept: application/json" -H "Referer: %API_URL%"') DO SET HTTP_CODE=%%H
CALL :log_message INFO "HTTPC: %HTTP_CODE%"
IF NOT "%HTTP_CODE%"=="200" (
    CALL :log_message ERROR "API Call Error - HTTPC: %HTTP_CODE%"
    EXIT /B %EXIT_CODE_ERROR%
)
EXIT /B
