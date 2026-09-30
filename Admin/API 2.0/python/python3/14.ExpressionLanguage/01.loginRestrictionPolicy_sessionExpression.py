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
# This script demonstrates SecureTransport's Expression Language (EL) used in
# a login restriction rule: a session-count guard written as
#   ${currentSessions <= 3}
# Login restriction rules are the one place in the product where a raw EL
# expression is a first class field on its own - most other places embed EL
# inside a string field on a bigger object (a route condition, a rename
# pattern), which the other scripts in this folder demonstrate instead.
#
# It creates a throwaway policy, adds the rule, shows it, then deletes the
# whole policy - a fresh policy always starts with an empty rules array and
# is not attached to anything, so it has no effect on any real login while
# it exists.
#
# APIs used - /myself ( ST login and logout )
#             /loginRestrictionPolicies ( POST, GET, PATCH, DELETE )
#
# Usage: python3 01.loginRestrictionPolicy_sessionExpression.py
#
# Notes:
# - Confirmed directly against a real server: POST /loginRestrictionPolicies
#   requires "type" (ALLOW_THEN_DENY or DENY_THEN_ALLOW) and a policy starts
#   with rules: [].
# - Unlike the bash version of this example, no backslash-doubling or shell
#   quoting games are needed here at all: the requests library's json=
#   parameter serializes this dict correctly no matter what characters the
#   expression string contains, since it is just a Python string, not
#   something assembled as literal JSON text by hand.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

POLICY = "ZZTEST_EL_sessionLimit"

config = el_client.load_config()
client = el_client.ELClient(config)

print("Creating a throwaway login restriction policy...")
response = client.post("loginRestrictionPolicies", {"name": POLICY, "type": "ALLOW_THEN_DENY"})
print(response.status_code, response.text)

print("\nAdding a rule that only allows login while fewer than 4 sessions are active...")
response = client.patch("loginRestrictionPolicies/" + POLICY, [{
    "op": "add",
    "path": "/rules/0",
    "value": {
        "name": "sessions fewer than 4",
        "isEnabled": True,
        "type": "ALLOW",
        "clientAddress": "*",
        "expression": "${currentSessions <= 3}",
        "description": "Only allow if less than 4 sessions",
    },
}])
print(response.status_code)

print("\nReading the policy back...")
response = client.get("loginRestrictionPolicies/" + POLICY)
print(response.text)

print("\nCleaning up the throwaway policy...")
response = client.delete("loginRestrictionPolicies/" + POLICY)
print(response.status_code)

client.logout()
