@echo off
REM ==============================================================================
REM Script Name: 06.sites_id_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script reads one transfer site, using the `/sites/{id}` endpoint with GET. It
REM demonstrates:
REM - Looking up the id by account and name
REM - Reading the whole site, and printing a short summary of it
REM - Asking for only some of its fields, with `fields=`
REM
REM Usage:
REM 06.sites_id_GET.bat [ACCOUNT [NAME]]
REM
REM   ACCOUNT  the account the site belongs to (default john)
REM   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.bat creates)
REM
REM Risk: read
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The site is looked up by account and name, and must be the only one with that name.
REM - Confirmed directly: an unknown id is a JSON 404, "Site with id X not found or not
REM   accessible.". `fields=` keeps the keys named (and always `type`); an unknown field is 400
REM   "Field nosuch does not exist.". `type=`, which the reference says is needed to read a field
REM   of one site type, is not: `type=http` or `type=bogus` on an SSH site answers the site.
REM - The password reads back encrypted (`{AES128}...`), never in clear. Send that text back
REM   and the password is kept (see 07.sites_id_PUT.bat).
REM - The fields differ by type: an SSH, FTP or HTTP site has host, port and folders; a custom
REM   site (S3, SMB...) has `customProperties` instead; run it on one of each to see.
REM - PowerShell is used to read the id and print the summary, in place of jq.
REM - Every call is checked: a status other than 200 (401, "Authentication required." as plain text, for refused credentials; 500)
REM   prints the status and the answer and ends the script with exit 1, so a refused read is not mistaken for an empty list.
REM - Exit codes: 0 when every answer is 200 and exactly one object is found, 1 otherwise, 2 when there are too many arguments (nothing sent).
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET RESPONSE_FILE=%TEMP%\site_%RANDOM%.json
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=SSH_PULL
IF NOT "%~3"=="" GOTO usage

CALL :main
SET RC=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RC%

:main
SET "URL=%MAIN_URL%"
SET CURL_OPTS=-G --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET SITE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SITE_ID=%%B
)
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% sites named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)
SET "URL=%MAIN_URL%/%SITE_ID%"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the site %NAME% ^(id %SITE_ID%^).
    EXIT /B 1
)
echo The site %NAME% of %ACCOUNT%, id %SITE_ID%:
powershell -NoProfile -Command "$s = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; function v($x) { if ($null -eq $x -or $x -eq '') { '-' } else { [string]$x } }; '  type:             ' + $s.type; '  protocol:         ' + $s.protocol; '  partner:          ' + (v $s.host) + ':' + (v $s.port); '  user:             ' + (v $s.userName); '  download folder:  ' + (v $s.downloadFolder); '  upload folder:    ' + (v $s.uploadFolder); '  max connections:  ' + $s.maxConcurrentConnection; '  access level:     ' + $s.accessLevel; '  password:         ' + (v $s.password)"

echo.
echo Only some of its fields, with fields=name,host,port:
SET "URL=%MAIN_URL%/%SITE_ID%"
SET CURL_OPTS=-G --data-urlencode "fields=name,host,port"
CALL :st_get
IF ERRORLEVEL 1 EXIT /B 1
powershell -NoProfile -Command "Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json | ConvertTo-Json -Compress"
EXIT /B 0

REM ------------------------------------------------------------------------------
REM A GET of the URL in URL, with the curl options in CURL_OPTS (for example -G --data-urlencode ...). The answer goes to
REM RESPONSE_FILE. A status other than 200 prints the status and the answer and returns 1.
REM ------------------------------------------------------------------------------
:st_get
SET HTTP_CODE=
SET OPTS=%CURL_OPTS%
SET CURL_OPTS=
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" %OPTS% -X GET "%URL%" -H "accept: application/json" -H "%REFERER_HEADER%"') DO SET HTTP_CODE=%%C
IF "%HTTP_CODE%"=="200" EXIT /B 0
echo HTTP %HTTP_CODE%
IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
EXIT /B 1

:usage
echo Usage: 06.sites_id_GET.bat [ACCOUNT [NAME]]
EXIT /B 2
