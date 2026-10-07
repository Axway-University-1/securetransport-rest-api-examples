@echo off
REM ==============================================================================
REM Script Name: 01.routeStepsMetadata_GET.bat
REM Author: Plamen Milenkov
REM Created: 2026-10-07
REM Location: Sofia
REM ==============================================================================
REM Description:
REM This script lists the route step types the server knows, using the
REM `/routeStepsMetadata` endpoint.
REM It demonstrates:
REM - Counting the step types and listing them, one line each: category, type, display name
REM - Showing everything the server says about one step type
REM - Using the `stepType` as the `type` of a step in a route
REM - Printing the smallest step of a type that the server accepts, as JSON, to put in a route's `steps`
REM
REM Usage:
REM 01.routeStepsMetadata_GET.bat [STEP_TYPE [minimal]]
REM
REM   STEP_TYPE  a step type to show in full, e.g. Compress (optional, case sensitive)
REM   minimal    print only the smallest step of that type, as JSON (the placeholders such as
REM              partner_account name objects that need not exist: see the Notes)
REM
REM Risk: read - the only operation of this resource is a GET
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - Confirmed directly: the answer is a plain array, not {resultSet, result}. Each entry has the same 12
REM   keys: stepType, stepCategory, stepDisplayName, endpointSchema, uiPagePath, stepPropertyBean,
REM   stepValidatorClassName, routeBuilderClassName, stepPropertyTransformer, stepModule, stepProducer and
REM   stepJarName. Most of the class names are null; they describe the server's internals.
REM - Confirmed directly: the lab lists 17 types, 13 Transformation and 4 Routing, in no order you should
REM   rely on. The reference's list of 14 differs: it lacks PullFromPartner, SendToFusion and
REM   setflowattributes (written in lower case, as is), so do not check a step type against it.
REM   ExecuteRoute, the step of a composite route, is not listed at all.
REM - Confirmed directly: the `stepType` is the `type` of a step in a route (09.CompositeRoutes): a route
REM   whose step has one of the listed types is checked against that type, and any other value answers
REM   400 "Route Step type is undefined.".
REM - Confirmed directly: the metadata does not say which fields a step needs. The server does: it names
REM   every missing one in validationErrors ("steps[0].compressionType must not be null"), and refuses a
REM   route whose step is incomplete with 400 (nothing is created). Adding the fields it named, one round
REM   after the other, gave the smallest step it accepts for each of the 17 types, and each was created,
REM   read back with GET /routes/<id> (same type and values) and deleted by
REM   tests/integration/checks/51.route_steps_metadata_scripts.py. Every step needs `type`, `status`
REM   (ENABLED or DISABLED) and `actionOnStepFailure` (FAIL or PROCEED); `conditionType` may be left out
REM   (it reads back ALWAYS). Below, "filter" is fileFilterExpression plus fileFilterExpressionType
REM   (GLOB, REGEXP or TEXT_FILES), and the rest is what each type needs besides the three:
REM     CharactersReplace   filter, inputCharset, findCharacterSequence
REM     Compress            filter, compressionType (ZIP, JAR, TAR, GZIP), compressionLevel (STORE, FASTEST,
REM                         FAST, NORMAL, GOOD, BETTER, BEST)
REM     Decompress          filter
REM     EncodingConversion  filter, inputCharset, outputCharset
REM     ExternalScript      scriptPath (no filter)
REM     LineEnding          filter, inputCharset, inputEolSequence, outputEolSequence
REM     LineFolding         filter, inputCharset, fileFoldWidth
REM     LinePadding         filter, inputCharset, linePaddingLength (reads back as a string)
REM     LineTruncating      filter, inputCharset, truncateLength
REM     PgpDecryption       fileFilterExpression only (the type may be left out, and reads back null)
REM     PgpEncryption       filter, compressionType ("0" none, "-1" preferred, "1" ZIP, "2" ZLIB, "3" BZIP2:
REM                         a name such as ZIP is 400 "Invalid compression type"), encryptKeyExpression and
REM                         encryptKeyExpressionType (ALIAS or EXPRESSION_WILDCARD), encryptKeyOwnerExpression
REM                         and encryptKeyOwnerExpressionType (NAME or EXPRESSION)
REM     Rename              filter, outputFileName
REM     setflowattributes   nothing more (actionOnStepFailure reads back inside customProperties)
REM     Publish             filter, filenameCollisionResolutionType, targetAccountExpressionType (NAME or
REM                         EXPRESSION), targetAccountExpression, targetFolderExpressionType (SIMPLE or
REM                         EXPRESSION), targetFolderExpression
REM     PullFromPartner     transferSiteExpressionType (LIST or EXPRESSION_WILDCARD), transferSiteExpression,
REM                         localFolderPathExpressionType and localFileNameExpressionType (SIMPLE or
REM                         EXPRESSION), targetAccountExpressionType and targetAccountExpression (no filter)
REM     SendToFusion        filter, fusionIntegrationName
REM     SendToPartner       filter, transferSiteExpressionType, transferSiteExpression ("<site>#!#CVD#!#")
REM   A filter given without its type is 400 "File filter type cannot be empty." (PgpDecryption excepted).
REM - Confirmed directly: creating a route does not look up what the step names: an account, a transfer site,
REM   a PGP key alias, a Fusion integration or a script path that does not exist is accepted (201), so the
REM   minimal steps printed with `minimal` use placeholders (partner_account, partner_site, partner_key,
REM   fusion_integration, /opt/scripts/process). Replace them before the route is used.
REM - Confirmed directly: fields= keeps the keys you name (an unknown one gives empty objects {}); stepType=,
REM   limit= and offset= are ignored and answer all 17. Accept: application/xml is 406. HEAD is 200;
REM   POST, PUT and DELETE are 405, and /routeStepsMetadata/<type> is 404: read only, no single read.
REM - PowerShell is used to print one step type per line, in place of jq.
REM ==============================================================================

SETLOCAL

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT
SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routeStepsMetadata
SET STEP_TYPE=%~1
SET SHOW=%~2
SET RESPONSE_FILE=%TEMP%\steps_%RANDOM%.json
REM The smallest step of each type the server accepts, confirmed on the lab (see the Notes)
SET MINIMAL_STEPS=[ordered]@{CharactersReplace=[ordered]@{type='CharactersReplace'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; findCharacterSequence='a'}; Compress=[ordered]@{type='Compress'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; compressionType='ZIP'; compressionLevel='NORMAL'}; Decompress=[ordered]@{type='Decompress'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'}; EncodingConversion=[ordered]@{type='EncodingConversion'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; outputCharset='UTF-16'}; ExternalScript=[ordered]@{type='ExternalScript'; status='ENABLED'; actionOnStepFailure='FAIL'; scriptPath='/opt/scripts/process'}; LineEnding=[ordered]@{type='LineEnding'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; inputEolSequence='LF'; outputEolSequence='CRLF'}; LineFolding=[ordered]@{type='LineFolding'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; fileFoldWidth=80}; LinePadding=[ordered]@{type='LinePadding'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; linePaddingLength=10}; LineTruncating=[ordered]@{type='LineTruncating'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; inputCharset='UTF-8'; truncateLength=80}; PgpDecryption=[ordered]@{type='PgpDecryption'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'}; PgpEncryption=[ordered]@{type='PgpEncryption'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; compressionType='0'; encryptKeyExpression='partner_key'; encryptKeyExpressionType='ALIAS'; encryptKeyOwnerExpression='partner_account'; encryptKeyOwnerExpressionType='NAME'}; Rename=[ordered]@{type='Rename'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; outputFileName='renamed.txt'}; setflowattributes=[ordered]@{type='setflowattributes'; status='ENABLED'; actionOnStepFailure='FAIL'}; Publish=[ordered]@{type='Publish'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; filenameCollisionResolutionType='OVERWRITE'; targetAccountExpressionType='NAME'; targetAccountExpression='partner_account'; targetFolderExpressionType='SIMPLE'; targetFolderExpression='/inbox'}; PullFromPartner=[ordered]@{type='PullFromPartner'; status='ENABLED'; actionOnStepFailure='FAIL'; transferSiteExpressionType='LIST'; transferSiteExpression='partner_site#!#CVD#!#'; localFolderPathExpressionType='SIMPLE'; localFileNameExpressionType='SIMPLE'; targetAccountExpressionType='NAME'; targetAccountExpression='partner_account'}; SendToFusion=[ordered]@{type='SendToFusion'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; fusionIntegrationName='fusion_integration'}; SendToPartner=[ordered]@{type='SendToPartner'; status='ENABLED'; actionOnStepFailure='FAIL'; fileFilterExpression='*'; fileFilterExpressionType='GLOB'; transferSiteExpressionType='LIST'; transferSiteExpression='partner_site#!#CVD#!#'}}

FOR /F %%C IN ('curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -o "%RESPONSE_FILE%" -w "%%{http_code}"') DO SET CODE=%%C

IF NOT "%CODE%"=="200" (
    echo HTTP %CODE%
    IF EXIST "%RESPONSE_FILE%" TYPE "%RESPONSE_FILE%"
    IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
    EXIT /B 1
)

IF NOT "%STEP_TYPE%"=="" GOTO one

FOR /F %%N IN ('powershell -NoProfile -Command "@(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json).Count"') DO echo Route step types: %%N
echo.
echo Category, step type (the type of a step in a route), display name:
powershell -NoProfile -Command "foreach ($s in @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json)) { '  {0}  {1}  {2}' -f $s.stepCategory, $s.stepType, $s.stepDisplayName }"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:one
powershell -NoProfile -Command "$s = @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json) | Where-Object { $_.stepType -ceq $env:STEP_TYPE }; if (-not $s) { exit 1 }"
IF ERRORLEVEL 1 GOTO not_found
IF "%SHOW%"=="minimal" GOTO minimal
echo Step type %STEP_TYPE%:
powershell -NoProfile -Command "$s = @(Get-Content -Raw $env:RESPONSE_FILE | ConvertFrom-Json) | Where-Object { $_.stepType -ceq $env:STEP_TYPE }; $s | ConvertTo-Json -Depth 10"
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 0

:minimal
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
powershell -NoProfile -Command "$t = %MINIMAL_STEPS%; if (-not $t.Contains($env:STEP_TYPE)) { exit 1 }; $t[$env:STEP_TYPE] | ConvertTo-Json -Depth 5"
IF ERRORLEVEL 1 GOTO no_minimal
EXIT /B 0

:no_minimal
echo This script keeps no minimal step for %STEP_TYPE%.
EXIT /B 1

:not_found
echo Not a step type of this server. Run the script with no argument to list them.
IF EXIST "%RESPONSE_FILE%" DEL "%RESPONSE_FILE%"
EXIT /B 1
