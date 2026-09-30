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
# This script demonstrates a transfer site's own downloadPattern field, using
# both pattern languages the EL documentation's pluggable-transfer-site
# "Download pattern examples" table shows: glob and regex. Unlike a route
# step's fileFilterExpression (03 and 04 in this folder), a site names its
# pattern type field downloadPatternType, and its accepted values are lower
# case, and spelled differently for the regex case.
#
#   glob:  *.xml         files ending in .xml
#   glob:  *.[0-9]        files with a single digit extension
#   regex: .*\.(xml|txt)  files ending in .xml or .txt
#
# APIs used - /myself ( ST login and logout )
#             /sites ( POST, GET, DELETE )
#
# Usage: python3 07.transferSites_downloadPattern.py
#
# Notes:
# - Confirmed directly against a real server: downloadPatternType is only
#   recognised on some site types (ssh here) - the same field name on an
#   http site is rejected outright as "Unsupported parameter".
# - downloadPatternType accepts lower case "glob" or "regex" - confirmed
#   directly, and "regex" specifically, not "regexp" (which is what a route
#   step's fileFilterExpressionType calls the same concept, in upper case).
#   Two fields for the same idea, two case conventions, two spellings for
#   the regex option - confirmed rather than assumed, since guessing either
#   from the other field would have been wrong.
# - This site is attached to the account "john", which must already exist,
#   the same assumption 06.TransferSites/01.sites_POST.sh makes.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)

SITES = [
    ("anyXml", "*.xml", "glob"),
    ("singleDigit", "*.[0-9]", "glob"),
    ("xmlOrTxt", r".*\.(xml|txt)", "regex"),
]

for suffix, pattern, pattern_type in SITES:
    name = "ZZTEST_EL_dlpattern_" + suffix
    print("\nCreating %s with downloadPattern: %s (%s)" % (name, pattern, pattern_type))
    response = client.post("sites", {
        "name": name,
        "type": "ssh",
        "protocol": "ssh",
        "account": "john",
        "host": config["st_server"],
        "port": "22",
        "downloadFolder": "/tmp",
        "downloadPattern": pattern,
        "downloadPatternType": pattern_type,
        "uploadFolder": "/",
        "userName": "john",
        "usePassword": True,
        "password": "placeholder",
    })
    print(response.status_code, response.text[:200])

print("\nReading all three back, and cleaning each up...")
for suffix, _, _ in SITES:
    name = "ZZTEST_EL_dlpattern_" + suffix
    response = client.get("sites", params={
        "name": name, "fields": "name,downloadPattern,downloadPatternType"})
    print("\n%s:" % name)
    print(response.text)

    response = client.get("sites", params={"name": name, "fields": "id"})
    result = response.json().get("result", [])
    if result:
        site_id = result[0]["id"]
        client.delete("sites/" + site_id)
        print("deleted %s (%s)" % (name, site_id))

client.logout()
