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
# This script demonstrates postTransformationActionRenameAsExpression - an EL
# expression that builds a new file name after a route step runs. Three
# worked examples from the EL documentation's predefined-functions appendix
# and file-name-examples table:
#
#   ${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}
#       strips the extension, adds a timestamp, then re-adds the extension.
#       Note extension() includes the leading dot, so no extra '.' is needed.
#
#   ${basename(transfer.target)}-${random()}.${extension(transfer.target)}
#       appends a random ID instead of a timestamp. This one, from the EL
#       appendix's own example, writes an extra literal '.' before
#       ${extension(...)} - inconsistent with extension() already including
#       the dot (see the gotchas skill); kept here exactly as documented so
#       the inconsistency is visible, not silently corrected.
#
#   ${account.name}_${basename(transfer.target)}
#       prefixes the file name with the current account's name.
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage: python3 06.routes_step_renameExpression.py
#
# Notes:
# - Confirmed directly against a real server: this field round trips exactly
#   as sent for all three examples - none of them use a regex, so no
#   backslash-doubling of any kind applies.
# - What the expression actually renames a file to is not tested here - that
#   needs a live transfer with a real file. This proves the field accepts
#   and stores the expression correctly, not what it produces.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

RENAMES = [
    ("timestamped", "${basename(transfer.target)}-${date('yyyyMMdd_HHmmss')}${extension(transfer.target)}"),
    ("randomId", "${basename(transfer.target)}-${random()}.${extension(transfer.target)}"),
    ("accountName", "${account.name}_${basename(transfer.target)}"),
]

for suffix, rename_expr in RENAMES:
    name = "ZZTEST_EL_rename_" + suffix
    print("\nCreating %s with postTransformationActionRenameAsExpression: %s" % (name, rename_expr))
    response = client.post("routes", {
        "name": name,
        "type": "SIMPLE",
        "conditionType": "ALWAYS",
        "steps": [{
            "type": "EncodingConversion",
            "status": "ENABLED",
            "conditionType": "ALWAYS",
            "usePrecedingStepFiles": False,
            "fileFilterExpression": "*",
            "fileFilterExpressionType": "GLOB",
            "inputCharset": "UTF-8",
            "outputCharset": "UTF-8",
            "postTransformationActionRenameAsExpression": rename_expr,
            "actionOnStepFailure": "PROCEED",
        }],
    })
    print(response.status_code)

print("\nReading all three back, and cleaning each up...")
for suffix, _ in RENAMES:
    name = "ZZTEST_EL_rename_" + suffix
    response = client.get("routes", params={
        "name": name, "fields": "name,steps.postTransformationActionRenameAsExpression"})
    print("\n%s:" % name)
    print(response.text)

    response = client.get("routes", params={"name": name, "fields": "id"})
    result = response.json().get("result", [])
    if result:
        route_id = result[0]["id"]
        client.delete("routes/" + route_id)
        print("deleted %s (%s)" % (name, route_id))

client.logout()
