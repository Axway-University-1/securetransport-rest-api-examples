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
# This isolates the single most error-prone thing about writing an EL regex:
# the EL documentation's own rule that "every backslash must be written
# twice" inside a ${...} string literal.
#
#   Layer 1 - Java regex: a literal dot needs one backslash:      \.
#   Layer 2 - the EL string literal holding that regex, per the EL
#             documentation's rule, doubles it:                   \\.
#             So the EL expression text a human reads is:
#                 ${transfer.target.matches('.*\\.txt')}
#
# In Python this is where it stops: write the EL expression text as a raw
# string with the backslash literally doubled, and requests' json=
# serializes it correctly no matter what it contains - there is no third
# escaping layer to get right, unlike the bash version of this example,
# where the same EL text then has to survive being typed as literal JSON in
# a shell command (see the bash script of the same name in this repository's
# bash Expression Language folder, and the gotchas skill).
#
# This script creates two throwaway routes so the difference is visible side
# by side:
#
#   ZZTEST_EL_doubled  - '.*\\.txt' - the correct, fully doubled form
#   ZZTEST_EL_single   - '.*\.txt'  - missing the EL layer's own doubling.
#       Per the EL documentation's own worked example ("Unescaped-dot form...
#       looser because the unescaped dot matches any character"), this
#       changes what the expression matches once it actually runs - it is
#       not merely cosmetic.
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage: python3 05.routes_step_condition_matches_backslashDoubling.py
#
# Notes:
# - Confirmed directly against a real server: both values round trip exactly
#   as sent, with the number of backslash characters preserved. What each
#   value actually matches against a real file name at transfer time is not
#   tested here - that needs a live transfer, a different kind of test than
#   this repository's integration checks run.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

ROUTES = [
    ("ZZTEST_EL_doubled", "${transfer.target.matches('.*\\\\.txt')}"),
    ("ZZTEST_EL_single", "${transfer.target.matches('.*\\.txt')}"),
]

for name, condition in ROUTES:
    print("\nCreating %s with condition: %s" % (name, condition))
    response = client.post("routes", {
        "name": name, "type": "SIMPLE", "conditionType": "EL", "condition": condition,
    })
    print(response.status_code)

print("\nReading both back - compare the number of backslashes in each condition value:")
for name, _ in ROUTES:
    response = client.get("routes", params={"name": name, "fields": "name,condition"})
    print(response.text)

print("\nCleaning up both throwaway routes...")
for name, _ in ROUTES:
    response = client.get("routes", params={"name": name, "fields": "id"})
    for result in response.json().get("result", []):
        client.delete("routes/" + result["id"])
        print("deleted %s (%s)" % (name, result["id"]))

client.logout()
