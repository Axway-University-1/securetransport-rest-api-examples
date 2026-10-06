@echo off
REM ==============================================================================
REM Script Name: 01.transfers_operations_POST_pull.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script starts a pull from a partner, on demand, using the
REM `/transfers/operations?operation=pull` endpoint. The files the site matches
REM are downloaded into a folder of the account.
REM
REM Usage:
REM 01.transfers_operations_POST_pull.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The account "john" and its site SSH_PULL must already exist. Run
REM   06.TransferSites\02.sites_POST_ssh.bat first.
REM - With awaitResult false, SecureTransport answers 202 as soon as the pull is
REM   accepted, and the pull runs on in the background. Follow it in File
REM   Tracking, or with 16.TransferLogs\01.logs_transfers_GET.bat.
REM - When the destination folder is subscribed to an application, as
REM   07.Subscriptions\02.subscriptions_POST.bat sets up for /inbox, what arrives
REM   there is routed.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET ACCOUNT=john
SET PULL_SITE=SSH_PULL
SET DESTINATION_FOLDER=/inbox

echo Pulling with the site '%PULL_SITE%' into '%DESTINATION_FOLDER%' of '%ACCOUNT%'...
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "https://%ST_SERVER%:%ST_PORT%/api/v2.0/transfers/operations?operation=pull" ^
  -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
  -w "\nHTTP %%{http_code}\n" ^
  -d "{\"accountName\":\"%ACCOUNT%\",\"site\":\"%PULL_SITE%\",\"destinationDirectory\":\"%DESTINATION_FOLDER%\",\"awaitResult\":false}"
