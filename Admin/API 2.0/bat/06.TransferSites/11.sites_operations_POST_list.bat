@echo off
REM ==============================================================================
REM Script Name: 11.sites_operations_POST_list.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists a folder on the partner of a saved transfer site, using the
REM `/sites/operations` endpoint with operation=listRemoteFolder: the server connects, logs
REM in, lists the site's download (or upload) folder, and prints what it finds.
REM
REM Usage:
REM 11.sites_operations_POST_list.bat [ACCOUNT [NAME [FOLDER [LIMIT [FOLDERS]]]]]
REM
REM   ACCOUNT  the account the site belongs to (default john)
REM   NAME     the site (default SSH_PULL, which 02.sites_POST_ssh.bat creates)
REM   FOLDER   downloadFolder or uploadFolder (default downloadFolder)
REM   LIMIT    how many entries to list, -1 for all (default 20)
REM   FOLDERS  true to list the folders too, false for the files only (default true)
REM
REM Risk: read - opens a connection to the partner, changes nothing
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - SSH, FTP and HTTP sites can be listed this way (the reference says SSH and FTP; an HTTP
REM   site lists the partner's folder too). The site's saved login is used; nothing secret is sent.
REM - Confirmed directly: the folder named by the site is listed (`remoteFolder` in the answer),
REM   and the answer carries `resultSet` and `result` like a collection, with the entries' name,
REM   size (text such as "12.00 bytes"), permissions and last modified time. Leaving
REM   `folderToList` out lists the UPLOAD folder, not the download folder the reference gives as
REM   its default; so does a value other than downloadFolder. The script always sends it.
REM - A folder that does not exist is still 200, with `remoteFolder` set, an empty result, and
REM   `errorDetails` "No such file: Specified file path is invalid.". A site with no folder of
REM   the kind asked for is 400 "Remote folder value cannot be empty for a non saved site." (the
REM   text says "non saved" though the site is saved); a `limit` that is not a number is a bare 404.
REM   `includesFolderNamesInResult` is not true by default either: left out, the folders are
REM   missing from the answer (the reference says true), so the script always sends it.
REM   `orderByLastModified=ascending` or `descending` sorts by time (listed by name otherwise).
REM   `limit=-1` lists all; the reference gives 50 as the default (the option
REM   ListRemoteFolder.Result.Files.Limit).
REM - PowerShell is used to read the id and print one line per entry, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/sites
SET ACCOUNT=%~1
IF "%ACCOUNT%"=="" SET ACCOUNT=john
SET NAME=%~2
IF "%NAME%"=="" SET NAME=SSH_PULL
SET FOLDER_TO_LIST=%~3
IF "%FOLDER_TO_LIST%"=="" SET FOLDER_TO_LIST=downloadFolder
IF NOT "%FOLDER_TO_LIST%"=="downloadFolder" IF NOT "%FOLDER_TO_LIST%"=="uploadFolder" (
    echo FOLDER is downloadFolder or uploadFolder, not %FOLDER_TO_LIST%.
    EXIT /B 2
)
SET LIMIT=%~4
IF "%LIMIT%"=="" SET LIMIT=20
powershell -NoProfile -Command "if ($env:LIMIT -match '^-?[0-9]+$') { exit 0 } else { exit 1 }"
IF ERRORLEVEL 1 (
    echo LIMIT is a number, not %LIMIT%.
    EXIT /B 2
)
SET FOLDERS=%~5
IF "%FOLDERS%"=="" SET FOLDERS=true
IF NOT "%FOLDERS%"=="true" IF NOT "%FOLDERS%"=="false" (
    echo FOLDERS is true or false, not %FOLDERS%.
    EXIT /B 2
)
SET LOOKUP_FILE=%TEMP%\site_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "account=%ACCOUNT%" --data-urlencode "name=%NAME%" --data-urlencode "fields=id,name" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET SITE_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.name -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET SITE_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% sites named %NAME% on the account %ACCOUNT%; this script acts on exactly one.
    EXIT /B 1
)
SET SITE_FILE=%TEMP%\site_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%SITE_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%SITE_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the site %NAME% ^(id %SITE_ID%^).
    IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\site_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\site_list_%RANDOM%.json
powershell -NoProfile -Command "$s = Get-Content -Raw $env:SITE_FILE | ConvertFrom-Json; $b = [ordered]@{ id = $s.id; name = $s.name; host = [string]$s.host; port = [string]$s.port; protocol = $s.protocol; account = $s.account }; $b | ConvertTo-Json -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"
IF EXIST "%SITE_FILE%" DEL "%SITE_FILE%"

echo Listing the %FOLDER_TO_LIST% of the site %NAME% of %ACCOUNT%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%/operations?operation=listRemoteFolder&folderToList=%FOLDER_TO_LIST%&limit=%LIMIT%&includesFolderNamesInResult=%FOLDERS%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
echo HTTP %HTTP_CODE%
IF NOT "%HTTP_CODE%"=="200" (
    type "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
powershell -NoProfile -Command "$r = Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json; '  connection:  ' + $r.connectionStatus; '  folder:      ' + $r.remoteFolder; if ($r.errorDetails) { '  error:       ' + $r.errorDetails }; '  entries:     ' + $r.resultSet.returnCount + ' of ' + $r.resultSet.totalCount; if ($r.result) { foreach ($f in @($r.result)) { '    ' + $f.fileName + '  ' + $f.fileSize + '  ' + $f.filePermissions + '  ' + $f.lastModifiedTime } }; if ($r.connectionStatus -eq 'success' -and -not $r.errorDetails) { exit 0 } else { exit 1 }"
SET RESULT=%ERRORLEVEL%
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B %RESULT%
