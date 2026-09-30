#!/usr/bin/env python3
##################################################################################
#  IMPORTANT NOTE: The included software is provided AS-IS, with no implied or   #
#  expressed warranty, and is not covered under any Axway service level          #
#  agreements (SLAs). This software tool is intended to meet certain specific    #
#  functional requirements, and extensive testing outside of the expected and    #
#  documented use cases has not been performed, and it may contain errors.       #
#  Customers are advised to perform appropriate backups prior to using this      #
#  tool, and perform ample testing after execution to assure that data has not   #
#  been lost and data integrity has not been jeopardized. Axway will not         #
#  be responsible for any loss or damage to data that is a result of this tool.  #
##################################################################################
#
# This script demonstrates a route step's fileFilterExpression using GLOB
# syntax - the simpler of the two pattern languages a step can filter files
# with (the other is REGEXP, see
# 04_routes_step_fileFilterExpression_regexp.py in this folder). One
# throwaway route per glob pattern from the EL documentation's "Pluggable
# transfer sites, Download pattern examples" table, each on a single
# EncodingConversion step:
#
#   *.xml       any file ending in .xml
#   foo.??      "foo." followed by exactly two characters
#   *.[0-9]     any file with a single digit extension
#   *.[!0-9]    any file with a single non-digit-character extension
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage: python3 03.routes_step_fileFilterExpression_glob.py
#
# Notes:
# - Confirmed directly against a real server: fileFilterExpressionType only
#   accepts GLOB, REGEXP or TEXT_FILES - not "REGEX".
# - fileFilterExpression is a plain glob/regex string, not wrapped in
#   ${...} - it is evaluated by the file filter itself, not by the EL
#   engine, so none of the backslash-doubling rules that apply inside an EL
#   string literal apply here. See the gotchas skill for the confirmed
#   distinction, and 05_routes_step_condition_matches_backslashDoubling.py
#   for what does need doubling.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

PATTERNS = [
    ("anyXml", "*.xml"),
    ("fooDotTwoAny", "foo.??"),
    ("singleDigit", "*.[0-9]"),
    ("notDigit", "*.[!0-9]"),
]

for suffix, pattern in PATTERNS:
    name = "ZZTEST_EL_glob_" + suffix
    print("\nCreating %s with fileFilterExpression: %s" % (name, pattern))
    response = client.post("routes", {
        "name": name,
        "type": "SIMPLE",
        "conditionType": "ALWAYS",
        "steps": [{
            "type": "EncodingConversion",
            "status": "ENABLED",
            "conditionType": "ALWAYS",
            "usePrecedingStepFiles": False,
            "fileFilterExpression": pattern,
            "fileFilterExpressionType": "GLOB",
            "inputCharset": "UTF-8",
            "outputCharset": "UTF-8",
            "actionOnStepFailure": "PROCEED",
        }],
    })
    print(response.status_code)

print("\nReading all four back, and cleaning each up...")
for suffix, _ in PATTERNS:
    name = "ZZTEST_EL_glob_" + suffix
    response = client.get("routes", params={
        "name": name, "fields": "name,steps.fileFilterExpression,steps.fileFilterExpressionType"})
    print("\n%s:" % name)
    print(response.text)

    response = client.get("routes", params={"name": name, "fields": "id"})
    result = response.json().get("result", [])
    if result:
        route_id = result[0]["id"]
        client.delete("routes/" + route_id)
        print("deleted %s (%s)" % (name, route_id))

client.logout()
