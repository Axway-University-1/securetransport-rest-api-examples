@echo off
REM ==============================================================================
REM Script Name: 03.statisticsSummary_operations_POST_testConnection.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script tests the connection to the Amplify Platform, where the usage report is sent, using the
REM `/statisticsSummary/operations` endpoint with operation=testConnection: the server asks the platform for a token
REM with the client id and secret, and says whether it worked. Nothing is saved: the settings in use do not change.
REM It demonstrates:
REM - Testing the credentials saved on the server (the StatisticsSummaryReport options), by giving none
REM - Testing other credentials, the secret read from the environment
REM
REM Usage:
REM 03.statisticsSummary_operations_POST_testConnection.bat [CLIENT_ID [NETWORK_ZONE [ENV_ID]]]
REM
REM   CLIENT_ID     test this client id (optional; the saved one is used when left out)
REM   NETWORK_ZONE  go through this network zone (optional)
REM   ENV_ID        the environment id (optional)
REM
REM   The client secret is read from the environment, never from an argument:
REM     SET AMPLIFY_CLIENT_SECRET=the secret
REM
REM Risk: read - the server connects to the Amplify Platform; nothing is saved
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - PowerShell is used to build the body and read the answer, in place of jq.
REM - The body is JSON: `type` (must be testConnection) and, when given, `clientId`, `clientSecret`, `networkZone` and `envId`.
REM   Whatever is left out is taken from the server's own StatisticsSummaryReport options (ClientId, ClientSecret, NetworkZone,
REM   EnvironmentId, Platform.Authentication, Platform.API). They are set by 13.Configurations/02.configurations_PATCH_UsageReporting.bat.
REM   With no argument and no secret this tests the saved credentials, and SENDS THE SAVED SECRET to the platform's login address.
REM - Confirmed directly: the server really connects. It POSTs `grant_type=client_credentials&client_id=...&client_secret=...` as a
REM   form to `StatisticsSummaryReport.Platform.Authentication` (a stand-in at that address saw it, with the ids given in the body, or
REM   the saved ones), then, with the token, calls `Platform.API`. The lab reaches the real platform: placeholder credentials get back
REM   `{"error":"invalid_client","error_description":"Invalid client or Invalid client credentials","code":401}`.
REM - Confirmed directly: **a refusal by the platform is relayed with the platform's own status and body**: the 401 above is the
REM   platform's, not your administrator login being refused, and a 500 from the token address came back as 500 with its own body
REM   (`{"error":"boom","code":500}`); this script prints the platform's `error` and `error_description` for those. A token
REM   that the platform's API does not accept (a stand-in handed out `fake`) is 401 `{"code":401,"description":"Invalid access token"}`.
REM - Confirmed directly: **a failure the server finds itself is 406** (not 400) with `validationErrors`: "Test connection to the
REM   Amplify Platform failed. Please check if the StatisticsSummaryReport.Platform.* server configuration options are set correctly or
REM   re-enter your client secret and try again.". That is what a body with no `type` (even `{}`), a `type` that is not exactly testConnection
REM   (`nope`, `TESTCONNECTION`), or a `networkZone` that is not empty gets: in each case with no call to the token address first.
REM   The server sends nothing to a zone given; one that does not exist is a failure.
REM - Confirmed directly: `clientId` and `clientSecret` may be given one without the other (the other is the saved one). With a `type` that is wrong or missing
REM   AND a `clientId` or `clientSecret` the answer is 400 "Unsupported parameter - clientId", not 406. A missing `operation` is 400
REM   "Invalid operation. Valid operation is: testConnection.", but `operation=nope` and `operation=TestConnection` still ran the
REM   test: the value is not checked, only that there is one. GET and HEAD are 405.
REM - NOT SEEN: a connection that works. That needs a real client id and secret from the platform (a stand-in token address is not
REM   enough: the server then calls `Platform.API`, which must be HTTPS and reachable). The reference gives the answer as `{"message": ...}`
REM   with 200 or 202, and this script prints the message and exits 0 for either.
REM - Exit codes: 0 when the server answered 200 or 202, 1 when it refuses or the test fails.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/statisticsSummary/operations
SET CLIENT_ID=%~1
SET NETWORK_ZONE=%~2
SET ENV_ID=%~3
IF NOT "%~4"=="" (
    echo Usage: 03.statisticsSummary_operations_POST_testConnection.bat [CLIENT_ID [NETWORK_ZONE [ENV_ID]]]
    EXIT /B 2
)
SET BODY_FILE=%TEMP%\statsum_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\statsum_%RANDOM%.json
powershell -NoProfile -Command "$b = [ordered]@{ type = 'testConnection' }; if ($env:CLIENT_ID) { $b.clientId = $env:CLIENT_ID }; if ($env:AMPLIFY_CLIENT_SECRET) { $b.clientSecret = $env:AMPLIFY_CLIENT_SECRET }; if ($env:NETWORK_ZONE) { $b.networkZone = $env:NETWORK_ZONE }; if ($env:ENV_ID) { $b.envId = $env:ENV_ID }; $b | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

IF "%CLIENT_ID%"=="" (
    echo Testing the connection to the Amplify Platform with the saved settings...
) ELSE (
    echo Testing the connection to the Amplify Platform as client %CLIENT_ID%...
)
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%?operation=testConnection" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
echo HTTP %HTTP_CODE%
IF "%HTTP_CODE%"=="200" GOTO worked
IF "%HTTP_CODE%"=="202" GOTO worked
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.error) { 'The platform answered: {0}: {1}' -f $r.error, $r.error_description } elseif ($r.validationErrors) { $r.validationErrors[0] } elseif ($r.description) { $r.description } elseif ($r.message) { $r.message } } catch { }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
:worked
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.message) { $r.message } else { $r }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
