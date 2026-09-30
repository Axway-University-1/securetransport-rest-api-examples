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
# This script demonstrates a route step's fileFilterExpression using REGEXP
# syntax - a plain (Java) regular expression, not a glob and not an EL
# expression. Three patterns from the EL documentation:
#
#   .*\.(xml|txt)                          names ending in .xml or .txt (alternation)
#   (?i)data\.xml                          data.xml, case insensitive
#   ^(?!.*__TID\d{6}__[A-Za-z0-9]{16}).*$  everything except one specific
#                                          generated-name shape (negative lookahead)
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage: python3 04.routes_step_fileFilterExpression_regexp.py
#
# Notes:
# - Confirmed directly against a real server: fileFilterExpression with
#   fileFilterExpressionType=REGEXP is a raw regular expression string,
#   stored exactly as sent. A single backslash before a literal dot, written
#   as a normal Python string with one backslash (Python's own \\ escape
#   producing one character), is correct - the bash version of this example
#   needs the same single backslash doubled in its *shell* source purely
#   because hand-written curl -d text has no automatic JSON encoder; here,
#   requests' json= parameter does that encoding correctly no matter what
#   the string contains, so there is nothing extra to get right.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

PATTERNS = [
    ("xmlOrTxt", r".*\.(xml|txt)"),
    ("caseInsensitive", r"(?i)data\.xml"),
    ("negativeLookahead", r"^(?!.*__TID\d{6}__[A-Za-z0-9]{16}).*$"),
]

for suffix, pattern in PATTERNS:
    name = "ZZTEST_EL_regexp_" + suffix
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
            "fileFilterExpressionType": "REGEXP",
            "inputCharset": "UTF-8",
            "outputCharset": "UTF-8",
            "actionOnStepFailure": "PROCEED",
        }],
    })
    print(response.status_code)

print("\nReading all three back, and cleaning each up...")
for suffix, _ in PATTERNS:
    name = "ZZTEST_EL_regexp_" + suffix
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
