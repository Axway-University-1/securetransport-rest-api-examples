@echo off
REM ==============================================================================
REM Script Name: 02.routes_POST.bat
REM Author: Plamen Milenkov
REM Created: 2025-09-15
REM Location: Sofia
REM ==============================================================================
REM Description:
REM Composite Routes are a type of route that allows you to inherit a Route
REM Template and extend it with additional routes if needed.
REM
REM This script shows how to create a composite route using the `/routes`
REM endpoint. It demonstrates:
REM - Looking up the ID of an existing route template by name
REM - Creating a composite route that inherits a template without extending it
REM - Creating a simple route and reading its new ID from the Location header
REM - Creating a composite route that inherits a template and extends it with
REM   that simple route, through an ExecuteRoute step
REM
REM Usage:
REM 02.routes_POST.bat
REM
REM Notes:
REM - Ensure that set_variables.bat is correctly configured and called.
REM - The route template must already exist. Run 08.RouteTemplates first.
REM - The account "john" must already exist.
REM - PowerShell is used to read JSON and headers, in place of jq.
REM ==============================================================================

CALL ..\set_variables.bat

set REFERER_HEADER=Referer: THIS_IS_A_RANDOM_TEXT

SET MAIN_URL=https://%ST_SERVER%:%ST_PORT%/api/v2.0/routes

REM ==============================================================================
REM First, get the ID of the Route Template we need
REM ==============================================================================
SET ROUTE_TEMPLATE_NAME=RouteFromAccountant

curl -s -k -u "%ST_USER%:%ST_PASSWORD%" -X GET "%MAIN_URL%?fields=id&name=%ROUTE_TEMPLATE_NAME%" -H "accept: application/json" -H "%REFERER_HEADER%" > template.json

FOR /F "tokens=*" %%I IN ('powershell -Command "(Get-Content template.json -Raw | ConvertFrom-Json).result[0].id"') DO SET ROUTE_TEMPLATE_ID=%%I

IF "%ROUTE_TEMPLATE_ID%"=="" (
    echo Error: Could not retrieve Route Template ID for '%ROUTE_TEMPLATE_NAME%'. Please check if the route template exists.
    IF EXIST template.json DEL template.json
    EXIT /B 1
)
echo Route Template ID for '%ROUTE_TEMPLATE_NAME%': %ROUTE_TEMPLATE_ID%
echo.

REM ==============================================================================
REM Example 1, without extension
REM Simple POST to create a package route in SecureTransport
REM ==============================================================================
echo Creating a composite route without extension...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{ \"account\": \"john\", \"name\": \"CompositeRoute_WithoutExtension\", \"type\": \"COMPOSITE\", \"conditionType\": \"MATCH_ALL\", \"routeTemplate\": \"%ROUTE_TEMPLATE_ID%\" }"
echo.

REM ==============================================================================
REM Example 2, with extension
REM To create a composite route with an extension, we will first create a simple
REM route that will be used as an extension.
REM ==============================================================================
echo Creating a simple route...
curl -s -D response_headers.txt -o nul -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{ \"name\": \"SimpleRouteName\", \"type\": \"SIMPLE\", \"conditionType\": \"ALWAYS\", \"steps\": [{ \"type\": \"EncodingConversion\", \"status\": \"ENABLED\", \"conditionType\": \"ALWAYS\", \"usePrecedingStepFiles\": false, \"fileFilterExpression\": \"string\", \"fileFilterExpressionType\": \"GLOB\", \"inputCharset\": \"UTF-8\", \"outputCharset\": \"UTF-8\", \"postTransformationActionRenameAsExpression\": \"string\", \"actionOnStepFailure\": \"PROCEED\" }] }"

REM The new resource URL is returned in the Location header. The ID is its last segment.
FOR /F "tokens=*" %%L IN ('powershell -Command "((Select-String -Path response_headers.txt -Pattern ''^^Location:'').Line -split '' '')[1].Trim()"') DO SET LOCATION=%%L

IF "%LOCATION%"=="" (
    echo Error: Could not read the Location header of the new simple route.
    IF EXIST response_headers.txt DEL response_headers.txt
    IF EXIST template.json DEL template.json
    EXIT /B 1
)
echo Resource created at: %LOCATION%

FOR /F "tokens=*" %%S IN ('powershell -Command "''%LOCATION%''.Split(''/'')[-1]"') DO SET SIMPLE_ROUTE_ID=%%S
echo New resource ID: %SIMPLE_ROUTE_ID%
echo.

echo Creating a composite route with extension...
curl -k -u "%ST_USER%:%ST_PASSWORD%" -X POST "%MAIN_URL%" -H "accept: application/json" -H "%REFERER_HEADER%" -H "Content-Type: application/json" ^
-d "{ \"account\": \"john\", \"name\": \"CompositeRoute_WithExtension\", \"type\": \"COMPOSITE\", \"conditionType\": \"MATCH_ALL\", \"routeTemplate\": \"%ROUTE_TEMPLATE_ID%\", \"steps\": [{ \"type\": \"ExecuteRoute\", \"status\": \"ENABLED\", \"executeRoute\": \"%SIMPLE_ROUTE_ID%\", \"autostart\": false }] }"

REM Remove the temporary files
IF EXIST template.json DEL template.json
IF EXIST response_headers.txt DEL response_headers.txt
