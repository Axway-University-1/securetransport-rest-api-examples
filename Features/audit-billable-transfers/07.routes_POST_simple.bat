@echo off
REM ==============================================================================
REM Script Name: 07.routes_POST_simple.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-01
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Creates the five simple routes these examples use, using the `/routes`
REM endpoint, one per scenario that has an outbound leg (scenario 2.1, only
REM inbound, has no route at all):
REM
REM   2.2  one SendToPartner step, to the first partner
REM   2.3  the SAME step twice: two SendToPartner steps, both to the first
REM        partner, both reading the files the route itself was given rather than
REM        each other's output, so the same file is pushed out twice
REM   2.4  Compress, then one SendToPartner step reading the compressed step's
REM        output
REM   2.5  Decompress, then one SendToPartner step reading the decompressed
REM        step's output (both files in one step, to the first partner)
REM   2.6  Decompress, then a SendToPartner step to the first partner, then a
REM        second SendToPartner step to the second partner - both reading the
REM        decompressed files, since a push does not transform or consume them
REM
REM Usage:
REM 07.routes_POST_simple.bat
REM
REM Risk: write
REM
REM Notes:
REM - Uses PowerShell to build the JSON bodies.
REM - A site is addressed as <site>#!#CVD#!# in transferSiteExpression - CVD is
REM   part of the separator, not a name (see Features/trigger-route-after-
REM   completed-pull, where this was confirmed against a real server).
REM - usePrecedingStepFiles: false means "the files this route execution was
REM   given", true means "the preceding step's own output". Both are documented
REM   fields on SendToPartner itself.
REM - Compress and Decompress step fields are from their own schema (not guessed):
REM   Compress combines its inputs into one archive with singleArchiveEnabled,
REM   named by singleArchiveName (not postTransformationActionRenameAsExpression,
REM   which is a separate field - presumably for renaming the individual inputs
REM   before they go into the archive, not the archive itself). Decompress needs
REM   no rename field: the names inside the archive are kept. Neither has been
REM   run against a real server yet.
REM - The ids are saved as BT_ID_SIMPLE_2 to BT_ID_SIMPLE_6 for the later steps.
REM ==============================================================================

REM Ends this script, without changing anything, on a server that is too old
CALL "%~dp0..\lib\st_feature_check.bat" 5.5-20260924
IF ERRORLEVEL 11 EXIT /B 1
IF ERRORLEVEL 10 EXIT /B 0
CALL "%~dp0settings.bat"

SET STEPS_FILE=%TEMP%\bt_steps_%RANDOM%.json

REM 2.2: one SendToPartner step
powershell -NoProfile -Command "@(@{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }) | ConvertTo-Json -Depth 10 -Compress" > "%STEPS_FILE%"
CALL :create_simple_route 2 "%STEPS_FILE%"

REM 2.3: the same step twice, both to the first partner
powershell -NoProfile -Command "@(@{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }) | ConvertTo-Json -Depth 10 -Compress" > "%STEPS_FILE%"
CALL :create_simple_route 3 "%STEPS_FILE%"

REM 2.4: Compress, into one named archive, then push the compressed output
powershell -NoProfile -Command "@(@{ type='Compress'; status='ENABLED'; conditionType='ALWAYS'; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; singleArchiveEnabled=$true; compressionType='ZIP'; compressionLevel='STORE'; singleArchiveName=$env:BT_FILE_COMPRESSED_NAME; actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }) | ConvertTo-Json -Depth 10 -Compress" > "%STEPS_FILE%"
CALL :create_simple_route 4 "%STEPS_FILE%"

REM 2.5: Decompress, then push both decompressed files to the first partner
powershell -NoProfile -Command "@(@{ type='Decompress'; status='ENABLED'; conditionType='ALWAYS'; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; filenameCollisionResolutionType='OVERWRITE'; actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }) | ConvertTo-Json -Depth 10 -Compress" > "%STEPS_FILE%"
CALL :create_simple_route 5 "%STEPS_FILE%"

REM 2.6: Decompress, then push to the first partner, then push to the second
powershell -NoProfile -Command "@(@{ type='Decompress'; status='ENABLED'; conditionType='ALWAYS'; usePrecedingStepFiles=$false; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; filenameCollisionResolutionType='OVERWRITE'; actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_1 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }, @{ type='SendToPartner'; status='ENABLED'; conditionType='ALWAYS'; autostart=$false; usePrecedingStepFiles=$true; fileFilterExpressionType='GLOB'; fileFilterExpression='*'; transferSiteExpressionType='LIST'; transferSiteExpression=($env:BT_PUSH_SITE_2 + '#!#CVD#!#'); actionOnStepFailure='FAIL' }) | ConvertTo-Json -Depth 10 -Compress" > "%STEPS_FILE%"
CALL :create_simple_route 6 "%STEPS_FILE%"

IF EXIST "%STEPS_FILE%" DEL "%STEPS_FILE%"
EXIT /B 0

:create_simple_route
SET SCENARIO_N=%1
SET STEPS_SRC=%~2
SET ROUTE_NAME=%BT_SIMPLE_ROUTE_PREFIX%%SCENARIO_N%
SET BODY_FILE=%TEMP%\bt_body_%RANDOM%.json
powershell -NoProfile -Command "@{ type='SIMPLE'; name=$env:ROUTE_NAME; conditionType='ALWAYS'; condition=$true; steps=(Get-Content -Raw $env:STEPS_SRC | ConvertFrom-Json) } | ConvertTo-Json -Depth 10 -Compress" > "%BODY_FILE%"

echo Creating the simple route %ROUTE_NAME%...
CALL "%~dp0..\lib\post_admin.bat" routes "%BODY_FILE%" BT_ID_SIMPLE_%SCENARIO_N%
IF EXIST "%BODY_FILE%" DEL "%BODY_FILE%"
EXIT /B 0
