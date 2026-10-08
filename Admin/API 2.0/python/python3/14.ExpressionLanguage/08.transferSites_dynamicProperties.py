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
# This script demonstrates the DXAGENT_TRANSFERSAPI_* pattern: a transfer
# site's own field holds a template like ${DXAGENT_TRANSFERSAPI_SERVER}
# instead of a fixed value, so the same site can be reused for many partners
# or file patterns - the actual value is supplied later, per request, in
# customProperties on a transfer operation (POST /transfers/operations),
# which this script does not call - only the site side of the pattern is
# shown here.
#
# APIs used - /myself ( ST login and logout )
#             /sites ( POST, GET, DELETE )
#
# Usage: python3 08.transferSites_dynamicProperties.py
#
# Risk: write - creates a throwaway transfer site on the account john and deletes it again, by the id it was created with; a site that was there already is never deleted
#
# Notes:
# - Confirmed directly against a real server: a site's host and
#   downloadPattern fields accept and store the literal template text
#   verbatim - "${DXAGENT_TRANSFERSAPI_SERVER}" is not evaluated or rejected
#   at creation time, it is just a string until a real transfer request
#   supplies the matching customProperties key.
# - Confirmed directly, and worth knowing before reaching for it: a plain
#   top level "customProperties" field on the site's own POST/PUT body is
#   rejected as "Unsupported parameter" - customProperties belongs to the
#   transfer *request* (the pull/push operation), not to the site object
#   itself.
# - This site's account "john" must already exist, the same assumption
#   06.TransferSites/01.sites_POST.sh makes.
#
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import el_client  # noqa: E402

config = el_client.load_config()
client = el_client.ELClient(config)
created = []

NAME = "ZZTEST_EL_dynamicSite"

try:
    print("Creating %s with templated host and downloadPattern fields..." % NAME)
    response = client.post("sites", {
        "name": NAME,
        "type": "http",
        "protocol": "http",
        "account": "john",
        "host": "${DXAGENT_TRANSFERSAPI_SERVER}",
        "port": "443",
        "downloadPattern": "${DXAGENT_TRANSFERSAPI_FILE}",
        "uploadFolder": "/",
        "userName": "john",
    })
    print(response.status_code)
    # A site of that name that is there already is refused: it is not ours, so stop
    client.expect(response, [201], "Creating " + NAME)
    client.track(created, "sites", response, NAME)

    print("\nReading it back - both fields should still hold the literal template text:")
    response = client.get("sites", params={"name": NAME, "fields": "name,host,downloadPattern"})
    client.expect(response, [200], "Reading " + NAME)
    print(response.text)

    print("\nCleaning up the throwaway site...")
finally:
    client.finish(created)
