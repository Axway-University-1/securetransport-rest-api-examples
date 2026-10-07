#!/bin/bash
# ==============================================================================
# Script Name: 01.routeStepsMetadata_GET.sh
# Author: Plamen Milenkov
# Created: 2026-10-07
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the route step types the server knows, using the
# `/routeStepsMetadata` endpoint.
# It demonstrates:
# - Counting the step types and listing them, one line each: category, type, display name
# - Showing everything the server says about one step type
# - Using the `stepType` as the `type` of a step in a route
# - Printing the smallest step of a type that the server accepts, as JSON, to put in a route's `steps`
#
# Usage:
# ./01.routeStepsMetadata_GET.sh [STEP_TYPE [minimal]]
#
#   STEP_TYPE  a step type to show in full, e.g. Compress (optional, case sensitive)
#   minimal    print only the smallest step of that type, as JSON (the placeholders such as
#              partner_account name objects that need not exist: see the Notes)
#
# Risk: read - the only operation of this resource is a GET
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - Confirmed directly: the answer is a plain array, not {resultSet, result}. Each entry has the same 12
#   keys: stepType, stepCategory, stepDisplayName, endpointSchema, uiPagePath, stepPropertyBean,
#   stepValidatorClassName, routeBuilderClassName, stepPropertyTransformer, stepModule, stepProducer and
#   stepJarName. Most of the class names are null; they describe the server's internals.
# - Confirmed directly: the lab lists 17 types, 13 Transformation and 4 Routing, in no order you should
#   rely on. The reference's list of 14 differs: it lacks PullFromPartner, SendToFusion and
#   setflowattributes (written in lower case, as is), so do not check a step type against it.
#   ExecuteRoute, the step of a composite route, is not listed at all.
# - Confirmed directly: the `stepType` is the `type` of a step in a route (09.CompositeRoutes): a route
#   whose step has one of the listed types is checked against that type, and any other value answers
#   400 "Route Step type is undefined.".
# - Confirmed directly: the metadata does not say which fields a step needs. The server does: it names
#   every missing one in validationErrors ("steps[0].compressionType must not be null"), and refuses a
#   route whose step is incomplete with 400 (nothing is created). Adding the fields it named, one round
#   after the other, gave the smallest step it accepts for each of the 17 types, and each was created,
#   read back with GET /routes/<id> (same type and values) and deleted by
#   tests/integration/checks/51.route_steps_metadata_scripts.py. Every step needs `type`, `status`
#   (ENABLED or DISABLED) and `actionOnStepFailure` (FAIL or PROCEED); `conditionType` may be left out
#   (it reads back ALWAYS). Below, "filter" is fileFilterExpression plus fileFilterExpressionType
#   (GLOB, REGEXP or TEXT_FILES), and the rest is what each type needs besides the three:
#     CharactersReplace   filter, inputCharset, findCharacterSequence
#     Compress            filter, compressionType (ZIP, JAR, TAR, GZIP), compressionLevel (STORE, FASTEST,
#                         FAST, NORMAL, GOOD, BETTER, BEST)
#     Decompress          filter
#     EncodingConversion  filter, inputCharset, outputCharset
#     ExternalScript      scriptPath (no filter)
#     LineEnding          filter, inputCharset, inputEolSequence, outputEolSequence
#     LineFolding         filter, inputCharset, fileFoldWidth
#     LinePadding         filter, inputCharset, linePaddingLength (reads back as a string)
#     LineTruncating      filter, inputCharset, truncateLength
#     PgpDecryption       fileFilterExpression only (the type may be left out, and reads back null)
#     PgpEncryption       filter, compressionType ("0" none, "-1" preferred, "1" ZIP, "2" ZLIB, "3" BZIP2:
#                         a name such as ZIP is 400 "Invalid compression type"), encryptKeyExpression and
#                         encryptKeyExpressionType (ALIAS or EXPRESSION_WILDCARD), encryptKeyOwnerExpression
#                         and encryptKeyOwnerExpressionType (NAME or EXPRESSION)
#     Rename              filter, outputFileName
#     setflowattributes   nothing more (actionOnStepFailure reads back inside customProperties)
#     Publish             filter, filenameCollisionResolutionType, targetAccountExpressionType (NAME or
#                         EXPRESSION), targetAccountExpression, targetFolderExpressionType (SIMPLE or
#                         EXPRESSION), targetFolderExpression
#     PullFromPartner     transferSiteExpressionType (LIST or EXPRESSION_WILDCARD), transferSiteExpression,
#                         localFolderPathExpressionType and localFileNameExpressionType (SIMPLE or
#                         EXPRESSION), targetAccountExpressionType and targetAccountExpression (no filter)
#     SendToFusion        filter, fusionIntegrationName
#     SendToPartner       filter, transferSiteExpressionType, transferSiteExpression ("<site>#!#CVD#!#")
#   A filter given without its type is 400 "File filter type cannot be empty." (PgpDecryption excepted).
# - Confirmed directly: creating a route does not look up what the step names: an account, a transfer site,
#   a PGP key alias, a Fusion integration or a script path that does not exist is accepted (201), so the
#   minimal steps printed with `minimal` use placeholders (partner_account, partner_site, partner_key,
#   fusion_integration, /opt/scripts/process). Replace them before the route is used.
# - Confirmed directly: fields= keeps the keys you name (an unknown one gives empty objects {}); stepType=,
#   limit= and offset= are ignored and answer all 17. Accept: application/xml is 406. HEAD is 200;
#   POST, PUT and DELETE are 405, and /routeStepsMetadata/<type> is 404: read only, no single read.
# - Requires `jq`, which prints one step type per line.
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/routeStepsMetadata"
STEP_TYPE="$1"
SHOW="$2"

# The smallest step of each type the server accepts, confirmed on the lab (see the Notes)
MINIMAL_STEPS='{"CharactersReplace":{"type":"CharactersReplace","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","findCharacterSequence":"a"},"Compress":{"type":"Compress","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","compressionType":"ZIP","compressionLevel":"NORMAL"},"Decompress":{"type":"Decompress","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB"},"EncodingConversion":{"type":"EncodingConversion","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","outputCharset":"UTF-16"},"ExternalScript":{"type":"ExternalScript","status":"ENABLED","actionOnStepFailure":"FAIL","scriptPath":"/opt/scripts/process"},"LineEnding":{"type":"LineEnding","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","inputEolSequence":"LF","outputEolSequence":"CRLF"},"LineFolding":{"type":"LineFolding","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","fileFoldWidth":80},"LinePadding":{"type":"LinePadding","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","linePaddingLength":10},"LineTruncating":{"type":"LineTruncating","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","inputCharset":"UTF-8","truncateLength":80},"PgpDecryption":{"type":"PgpDecryption","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*"},"PgpEncryption":{"type":"PgpEncryption","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","compressionType":"0","encryptKeyExpression":"partner_key","encryptKeyExpressionType":"ALIAS","encryptKeyOwnerExpression":"partner_account","encryptKeyOwnerExpressionType":"NAME"},"Rename":{"type":"Rename","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","outputFileName":"renamed.txt"},"setflowattributes":{"type":"setflowattributes","status":"ENABLED","actionOnStepFailure":"FAIL"},"Publish":{"type":"Publish","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","filenameCollisionResolutionType":"OVERWRITE","targetAccountExpressionType":"NAME","targetAccountExpression":"partner_account","targetFolderExpressionType":"SIMPLE","targetFolderExpression":"/inbox"},"PullFromPartner":{"type":"PullFromPartner","status":"ENABLED","actionOnStepFailure":"FAIL","transferSiteExpressionType":"LIST","transferSiteExpression":"partner_site#!#CVD#!#","localFolderPathExpressionType":"SIMPLE","localFileNameExpressionType":"SIMPLE","targetAccountExpressionType":"NAME","targetAccountExpression":"partner_account"},"SendToFusion":{"type":"SendToFusion","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","fusionIntegrationName":"fusion_integration"},"SendToPartner":{"type":"SendToPartner","status":"ENABLED","actionOnStepFailure":"FAIL","fileFilterExpression":"*","fileFilterExpressionType":"GLOB","transferSiteExpressionType":"LIST","transferSiteExpression":"partner_site#!#CVD#!#"}}'

RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X GET "${MAIN_URL}" -H "accept: application/json" -H "${REFERER_HEADER}" \
  -w "\n%{http_code}")
CODE="${RESPONSE##*$'\n'}"
BODY="${RESPONSE%$'\n'*}"

if [ "${CODE}" != "200" ]; then
    printf "HTTP %s\n%s\n" "${CODE}" "${BODY}"
    exit 1
fi

if [ -n "${STEP_TYPE}" ]; then
    FOUND=$(printf "%s" "${BODY}" | jq --arg t "${STEP_TYPE}" '[.[] | select(.stepType == $t)] | first // empty')
    if [ -z "${FOUND}" ]; then
        printf "Not a step type of this server. Run the script with no argument to list them.\n"
        exit 1
    fi
    if [ "${SHOW}" = "minimal" ]; then
        MINIMAL=$(printf "%s" "${MINIMAL_STEPS}" | jq --arg t "${STEP_TYPE}" '.[$t] // empty')
        if [ -z "${MINIMAL}" ]; then
            printf "This script keeps no minimal step for %s.\n" "${STEP_TYPE}"
            exit 1
        fi
        printf "%s\n" "${MINIMAL}"
        exit 0
    fi
    printf "Step type %s:\n" "${STEP_TYPE}"
    printf "%s\n" "${FOUND}" | jq .
    exit 0
fi

printf "Route step types: %s\n" "$(printf "%s" "${BODY}" | jq 'length')"
printf "\nCategory, step type (the type of a step in a route), display name:\n"
printf "%s" "${BODY}" | jq -r '.[] | "  \(.stepCategory)  \(.stepType)  \(.stepDisplayName)"'
