@echo off
REM ==============================================================================
REM Script Name: 04.sites_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-05
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes transfer sites using the `/sites/{id}` endpoint.
REM A site is deleted by its id, not its name, so it demonstrates:
REM - Looking up the id of a site by account and name
REM - Deleting the site by that id, printing the HTTP code and what was deleted
REM
REM Usage:
REM 04.sites_id_DELETE.bat
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - This cleans up the three sites that 01.sites_POST.bat and 02.sites_POST_ssh.bat create for the account
REM   "john": SSH_PULL and SSH_PUSH (02), and HTTP (01, which was left out of the cleanup before). Only ever point it at sites
REM   you created: an account that has a site of its own called HTTP loses it.
REM - A site that a subscription or a route still uses cannot be deleted. Delete
REM   those first (07.Subscriptions, 09.CompositeRoutes).
REM - The name filter ignores case and takes a * wildcard, so the exact name is picked out of what comes back, and a name that two sites
REM   match is not deleted (exit 1).
REM - PowerShell is used to read the id out of the response, in place of jq.
REM - Confirmed directly: a delete is 204 with no body; an id that is not there is a JSON 404, "Site with id X not found or not accessible.".
REM - Exit codes: 0 when every site was deleted or was not there, 1 when the server refuses a lookup or a delete, or a name is ambiguous.
REM   It takes no argument.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites

IF NOT "%~1"=="" (
    echo Usage: 04.sites_id_DELETE.bat
    EXIT /B 2
)

SET "ACCOUNT=%ST_EXAMPLE_ACCOUNT%"
IF "%ACCOUNT%"=="" SET "ACCOUNT=john"
SET RESPONSE_FILE=%TEMP%\sites_%RANDOM%.json
SET FAILED=0

FOR %%N IN (SSH_PULL SSH_PUSH HTTP) DO CALL :delete_site %%N

IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
IF NOT "%FAILED%"=="0" EXIT /B 1
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Looks the site named in %1 up by account and exact name, and deletes it
REM ------------------------------------------------------------------------------
:delete_site
SET NAME=%1
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF NOT "%HTTP_CODE%"=="200" (
    echo Could not look up the site '%NAME%' of '%ACCOUNT%': HTTP %HTTP_CODE%
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
REM The name filter ignores case and takes a * wildcard, so only the sites with exactly this name count
SET FOUND=0
SET SITE_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "@((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_ -ne $null -and $_.name -ceq $env:NAME }) | ForEach-Object { $_.id }"') DO (
    SET /A FOUND+=1
    SET SITE_ID=%%I
)
IF "%FOUND%"=="0" (
    echo The account '%ACCOUNT%' has no site '%NAME%'.
    EXIT /B 0
)
IF NOT "%FOUND%"=="1" (
    echo The account '%ACCOUNT%' has %FOUND% sites named '%NAME%'; none deleted.
    SET FAILED=1
    EXIT /B 0
)

echo Deleting the site '%NAME%' (%SITE_ID%)...
FOR /F "delims=" %%E IN ('powershell -NoProfile -Command "[uri]::EscapeDataString($env:SITE_ID)"') DO SET SITE_URI=%%E
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%SITE_URI%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" (
    CALL :show_error
    SET FAILED=1
    EXIT /B 0
)
echo Deleted the site '%NAME%'.
EXIT /B 0

REM ------------------------------------------------------------------------------
REM Prints the server's own messages from the answer in RESPONSE_FILE, or the text as it is
REM ------------------------------------------------------------------------------
:show_error
IF NOT EXIST "%RESPONSE_FILE%" EXIT /B 0
powershell -NoProfile -Command "try { $r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; if ($r.validationErrors) { $r.validationErrors } elseif ($r.message) { $r.message } } catch { Get-Content $env:RESPONSE_FILE }"
EXIT /B 0
