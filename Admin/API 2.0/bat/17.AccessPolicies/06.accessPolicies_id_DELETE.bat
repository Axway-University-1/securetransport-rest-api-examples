@echo off
REM ==============================================================================
REM Script Name: 06.accessPolicies_id_DELETE.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-06
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script deletes the database access policies 02.accessPolicies_POST.bat
REM adds, using the `/accessPolicies/{id}` endpoint. It demonstrates:
REM - Looking a rule up by its content, just before deleting it
REM - Deleting every matching rule safely, when ids move as rules are deleted
REM
REM Usage:
REM 06.accessPolicies_id_DELETE.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Only for a server on the embedded PostgreSQL database.
REM - Confirmed directly: an id is the rule's line in pg_hba.conf, and the rules
REM   after a deleted one move up. Deleting ids found in one listing therefore
REM   deletes the wrong rules from the second one on. This script lists the rules
REM   again before each delete, and deletes the last match first.
REM - Only ever point it at a rule you added: deleting one of the server's own
REM   can lock SecureTransport out of its own database.
REM - PowerShell is used to find the rules, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/accessPolicies

SET DATABASE=example_db
SET USER_NAME=example_user
SET RESPONSE_FILE=%TEMP%\policies_%RANDOM%.json
SET DELETED=0

:next_rule
REM Listed again each time: the ids have moved since the last delete
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%RESPONSE_FILE%"
SET POLICY_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { $all = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; $p = @($all | Where-Object { $_.database -eq $env:DATABASE -and $_.user -eq $env:USER_NAME }); if ($p.Count) { $p[-1].id } } catch { }"') DO SET POLICY_ID=%%I
IF "%POLICY_ID%"=="" GOTO :done

echo Deleting rule %POLICY_ID%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o nul -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X DELETE "%MAIN_URL%/%POLICY_ID%" -H "accept: */*" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="204" GOTO :failed
SET /A DELETED=%DELETED%+1
GOTO :next_rule

:done
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
echo Deleted %DELETED% rule(s) for %USER_NAME% on %DATABASE%.
EXIT /B 0

:failed
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
