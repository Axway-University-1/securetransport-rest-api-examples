@echo off
REM ==============================================================================
REM Script Name: 06.userClasses_id_PATCH.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script changes one property of a user class, using the `/userClasses/{id}`
REM endpoint with PATCH: a JSON Patch document that replaces one field. Unlike PUT
REM (05.userClasses_id_PUT.bat), it sends only what changes.
REM
REM Usage:
REM 06.userClasses_id_PATCH.bat [NAME [FIELD [VALUE]]]
REM
REM   NAME   the class (default example_userclass)
REM   FIELD  enabled (default), expression, order, userName, group, address, userType or className
REM   VALUE  the new value (default true); true or false for enabled, a number from 1 for order, none to empty the expression
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the value before, to put it back with. A change of `order` moves the class and the others shift: the one at that
REM   place and those after it go down by one, so patching VirtClass or RealClass would change which classes come first: do not.
REM - Confirmed directly: a success answers 204, with no body, and an empty patch is 204 too. `replace` works on every field of the class;
REM   `add` on one that is set overwrites it; `remove` of `/expression` gives the empty text (not null); `remove` of any other field is 400
REM   "group must not be null" (and so on). `replace` of `/id` is 204 and changes nothing; a path that does not exist is 400 `Missing field
REM   "nope"`; `enabled` with text that is no boolean is 400; an invalid expression, userType or a name another class has is 400 or 409
REM   and the class is unchanged; `className` renames it (the accounts in it are in it still, under the new name). An unknown id is 400, not
REM   the 404 the reference lists.
REM - Confirmed directly, the effect on a login: patching `expression`, `enabled`, `userName` or `userType` so that the account no longer fits
REM   puts its NEXT login (SFTP, HTTP and FTP alike) in the next matching class, and patching it back puts it in again. Of two classes that fit, the one with the lower
REM   `order` wins: patching `/order` of the second to 1 (or of the first to 2) swaps them. A session already open keeps its class. Check 60.
REM - PowerShell is used to read the id and build the patch, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_userclass
SET FIELD=%~2
IF "%FIELD%"=="" SET FIELD=enabled
SET VALUE=%~3
IF "%VALUE%"=="" SET VALUE=true
SET KIND=
IF "%FIELD%"=="enabled" SET KIND=boolean
IF "%FIELD%"=="order" SET KIND=number
FOR %%F IN (expression userName group address userType className) DO IF "%FIELD%"=="%%F" SET KIND=string
IF "%KIND%"=="" (
    echo FIELD is enabled, expression, order, userName, group, address, userType or className, not %FIELD%.
    EXIT /B 2
)
IF "%KIND%"=="boolean" IF NOT "%VALUE%"=="true" IF NOT "%VALUE%"=="false" (
    echo VALUE for enabled is true or false, not %VALUE%.
    EXIT /B 2
)
IF "%KIND%"=="number" (
    powershell -NoProfile -Command "if ($env:VALUE -match '^[0-9]{1,9}$' -and [int]$env:VALUE -ge 1) { exit 0 } else { exit 1 }"
    IF ERRORLEVEL 1 (
        echo VALUE for order is a number from 1, not %VALUE%.
        EXIT /B 2
    )
)

SET LOOKUP_FILE=%TEMP%\uclass_lookup_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -G -X GET "%MAIN_URL%" --data-urlencode "className=%NAME%" --data-urlencode "fields=id,className" ^
  -H "accept: application/json" -H "%REFERER_HEADER%" > "%LOOKUP_FILE%"
SET CLASS_ID=
SET FOUND=0
FOR /F "tokens=1,2" %%A IN ('powershell -NoProfile -Command "$r = @((Get-Content -Raw $env:LOOKUP_FILE | ConvertFrom-Json).result | Where-Object { $_.className -ceq $env:NAME }); if ($r.Count -eq 1) { [string]1 + [char]32 + $r[0].id } else { [string]$r.Count }"') DO (
    SET FOUND=%%A
    SET CLASS_ID=%%B
)
IF EXIST "%LOOKUP_FILE%" DEL "%LOOKUP_FILE%"
IF NOT "%FOUND%"=="1" (
    echo Found %FOUND% user classes named %NAME%; this script acts on exactly one.
    EXIT /B 1
)

SET CLASS_FILE=%TEMP%\uclass_%RANDOM%.json
curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%/%CLASS_ID%" -H "accept: application/json" -H "%REFERER_HEADER%" > "%CLASS_FILE%"
SET READ_ID=
FOR /F "delims=" %%I IN ('powershell -NoProfile -Command "try { (Get-Content -Raw $env:CLASS_FILE | ConvertFrom-Json).id } catch { }"') DO SET READ_ID=%%I
IF "%READ_ID%"=="" (
    echo Could not read the user class %NAME% ^(id %CLASS_ID%^).
    IF EXIST "%CLASS_FILE%" DEL "%CLASS_FILE%"
    EXIT /B 1
)
SET BODY_FILE=%TEMP%\uclass_body_%RANDOM%.json
SET RESPONSE_FILE=%TEMP%\uclass_response_%RANDOM%.txt
SET BEFORE=
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "$v = (Get-Content -Raw $env:CLASS_FILE | ConvertFrom-Json).($env:FIELD); if ($v -is [bool]) { ([string]$v).ToLower() } else { [string]$v }"') DO SET BEFORE=%%D
echo The %FIELD% of %NAME% is now '%BEFORE%'.
powershell -NoProfile -Command "$v = switch ($env:KIND) { 'boolean' { $env:VALUE -eq 'true' } 'number' { [int]$env:VALUE } default { if ($env:VALUE -eq 'none') { '' } else { $env:VALUE } } }; $op = [ordered]@{ op = 'replace'; path = '/' + $env:FIELD; value = $v }; ConvertTo-Json -InputObject @($op) -Compress | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Setting it to %VALUE%...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PATCH "%MAIN_URL%/%CLASS_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
echo HTTP %HTTP_CODE%
IF EXIST "%CLASS_FILE%" DEL "%CLASS_FILE%"
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
IF NOT "%HTTP_CODE%"=="204" (
    TYPE "%RESPONSE_FILE%"
    echo.
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
