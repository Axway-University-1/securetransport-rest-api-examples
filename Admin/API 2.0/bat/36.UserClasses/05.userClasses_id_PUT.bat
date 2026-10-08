@echo off
REM ==============================================================================
REM Script Name: 05.userClasses_id_PUT.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-08
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script replaces a user class, using the `/userClasses/{id}` endpoint with PUT:
REM it reads the class, changes the membership expression and/or whether it is enabled, and sends the
REM whole class back.
REM
REM Usage:
REM 05.userClasses_id_PUT.bat [NAME [EXPRESSION [ENABLED]]]
REM
REM   NAME        the class (default example_userclass)
REM   EXPRESSION  the new expression (default false); none empties it; - leaves it alone
REM   ENABLED     true or false; - (default) leaves it alone
REM
REM Risk: write
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - It prints the values before, to put them back with. Nothing to change (both left alone) is exit 2, nothing sent.
REM - PUT replaces the whole class. Confirmed directly: a body with only the five required fields (className, userType, userName,
REM   group, address) answers 204 and RESETS `expression` to the empty text and `enabled` to false; `order` is kept when left out. That is
REM   why the class is read first and sent back with one or two fields changed. `id` is dropped from the body (a body that carries the
REM   id of ANOTHER class is accepted and ignored: the path decides).
REM - Confirmed directly: a success answers 204, with no body. A body missing a required field is 400 listing it; an invalid
REM   expression is 400 "expression X is not valid." and the class is unchanged; `className` renames it (a name another class has, 409; the
REM   same name in other capitals is fine); `order` moves the class: 0 or 1 first, the ones in between shift, more than there are classes
REM   or a negative one is 400 "Order is not valid.". An unknown id is 400 "User Class with ID X does not exist.", not the 404 the
REM   reference lists. The reference leaves `enabled`, `expression` and `order` optional, as they are.
REM - Confirmed directly, the effect: after a PUT that makes the expression false, or `enabled` false, the next login (SFTP, HTTP or FTP alike) of an account the
REM   class fitted is in the next matching class (VirtClass); put back, it is in the class again, at once. A session already open keeps
REM   the class it had. Check 60 shows it.
REM - PowerShell is used to read the id and edit the class, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/userClasses
SET NAME=%~1
IF "%NAME%"=="" SET NAME=example_userclass
SET EXPRESSION=%~2
IF "%EXPRESSION%"=="" SET EXPRESSION=false
SET ENABLED=%~3
IF "%ENABLED%"=="" SET ENABLED=-
IF NOT "%ENABLED%"=="true" IF NOT "%ENABLED%"=="false" IF NOT "%ENABLED%"=="-" (
    echo ENABLED is true, false or -, not %ENABLED%.
    EXIT /B 2
)
IF "%EXPRESSION%"=="-" IF "%ENABLED%"=="-" (
    echo Nothing to change: give an EXPRESSION or ENABLED.
    EXIT /B 2
)
powershell -NoProfile -Command "if ($env:EXPRESSION.Length -gt 1024) { exit 1 } else { exit 0 }"
IF ERRORLEVEL 1 (
    echo EXPRESSION is 1024 characters at most.
    EXIT /B 2
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
SET BEFORE_EXPRESSION=
SET BEFORE_ENABLED=
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "(Get-Content -Raw $env:CLASS_FILE | ConvertFrom-Json).expression"') DO SET BEFORE_EXPRESSION=%%D
FOR /F "delims=" %%D IN ('powershell -NoProfile -Command "([string](Get-Content -Raw $env:CLASS_FILE | ConvertFrom-Json).enabled).ToLower()"') DO SET BEFORE_ENABLED=%%D
echo The expression of %NAME% is now '%BEFORE_EXPRESSION%', enabled is %BEFORE_ENABLED%.
powershell -NoProfile -Command "$p = Get-Content -Raw $env:CLASS_FILE | ConvertFrom-Json; if ($env:EXPRESSION -ne '-') { $p.expression = if ($env:EXPRESSION -eq 'none') { '' } else { $env:EXPRESSION } }; if ($env:ENABLED -ne '-') { $p.enabled = ($env:ENABLED -eq 'true') }; $p.PSObject.Properties.Remove('id'); $p | ConvertTo-Json -Compress -Depth 20 | Set-Content -Encoding ASCII $env:BODY_FILE"

echo Changing it...
SET HTTP_CODE=
FOR /F %%C IN ('curl -s -o "%RESPONSE_FILE%" -w "%%{http_code}" -k -u "%ST_USER%:%ST_PASSWORD%" -X PUT "%MAIN_URL%/%CLASS_ID%" -H "accept: */*" -H "%REFERER_HEADER%" -H "Content-Type: application/json" -d "@%BODY_FILE%"') DO SET HTTP_CODE=%%C
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
