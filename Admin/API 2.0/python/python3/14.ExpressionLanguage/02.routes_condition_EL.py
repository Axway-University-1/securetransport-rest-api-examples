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
# This script demonstrates using an Expression Language (EL) condition on a
# route itself, rather than the built-in ALWAYS / MATCH_ALL / MATCH_FIRST
# condition types. It creates three throwaway routes, each conditionType=EL
# with a different worked expression from the EL documentation:
#
#   1. ${account.disabled != '0'}          - a relational comparison (conditional)
#   2. ${!empty account.email}             - the empty operator (conditional)
#   3. ${transfer.transferredBytes ge 20}  - a numeric comparison (arithmetic)
#
# APIs used - /myself ( ST login and logout )
#             /routes ( POST, GET, DELETE )
#
# Usage: python3 02.routes_condition_EL.py
#
# Notes:
# - Confirmed directly against a real server: conditionType accepts
#   MATCH_ALL, MATCH_FIRST, ALWAYS or EL. When it is EL, the expression text
#   goes in a field simply named "condition".
# - This is the route-level condition (does the whole route run at all), a
#   different field from a route *step's* own conditionType/condition - see
#   03 and 04 in this folder for that, combined with a file filter.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

ROUTES = [
    ("ZZTEST_EL_route_disabled", "${account.disabled != '0'}"),
    ("ZZTEST_EL_route_hasEmail", "${!empty account.email}"),
    ("ZZTEST_EL_route_bytesGE20", "${transfer.transferredBytes ge 20}"),
]

for name, condition in ROUTES:
    print("\nCreating %s with condition: %s" % (name, condition))
    response = client.post("routes", {
        "name": name, "type": "SIMPLE", "conditionType": "EL", "condition": condition,
    })
    print(response.status_code)

print("\nReading all three back...")
for name, _ in ROUTES:
    response = client.get("routes", params={"name": name, "fields": "name,condition,conditionType"})
    print(response.text)

print("\nCleaning up all three throwaway routes...")
for name, _ in ROUTES:
    response = client.get("routes", params={"name": name, "fields": "id"})
    result = response.json().get("result", [])
    if result:
        route_id = result[0]["id"]
        client.delete("routes/" + route_id)
        print("deleted %s (%s)" % (name, route_id))

client.logout()
