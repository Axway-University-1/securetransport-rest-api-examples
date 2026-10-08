#! /usr/bin/python3
#
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
# V3.00 Plamen Milenkov  08-Oct-2026  Shows what it would change and changes nothing unless told to
#                                     (--apply). A PUT is only reported as done when the status is
#                                     204, and a refused one makes the exit code 1. Every failure
#                                     exits 1.
# V2.00 Ian Percival   16-Jun-2023   Fix errors + csrf compliant
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default
#                                    for ST after and including the 20230525 release.
# V1.00 Ian Percival   10-Nov-2021
#
# This script will scan all ssh transfer sites, looking to see if the cipher
# suites need to be updated: every SSH site whose key exchange algorithms are not the
# master list below is sent back (PUT) with the master list.
#
# APIs used - /myself POST DELETE ( ST login and logout )
#             /sites  GET, PUT
#
# Usage: python3 stReplaceSites.py [--apply]
#
#        Without --apply the script reads the SSH sites and says which it would change,
#        and sends nothing. Start there.
#
# Risk: write - replaces the key exchange algorithms of every SSH transfer site that differs from the master list (with --apply)
#
# Notes:
# - There is no filter by name: EVERY SSH site on the server is in scope. They can be real
#   partner connections, and a partner that does not offer one of these algorithms can no
#   longer be reached. Read the dry run, and keep the list of what it changed.
# - A PUT replaces the whole site, so the site read is sent back with the one field changed.
# - Exit codes: 0 done, 1 anything failed (a PUT that did not answer 204 included), 2 an
#   argument is not understood.
#
# Outputs:
#    The sites it changed or would change, and the number of SSH sites seen.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

import base64
import json
import os
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# All functions are defined below


# Send one request. Anything that keeps the call from completing is fatal: the script
# says what failed and exits 1. An HTTP status is not an exception, so the caller
# looks at it (see stExpect).
def stCall(session, method, url, **kwargs):
    try:
        response = getattr(session, method.lower())(url, verify=stVerify, timeout=stTimeout, **kwargs)
    except requests.exceptions.Timeout as et:
        print('Timeout talking to ' + url + ': ' + str(et))
        sys.exit(1)
    except requests.exceptions.ConnectionError as ec:
        print('I cannot connect to ' + url + ': ' + str(ec))
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print('The request to ' + url + ' failed: ' + str(e))
        sys.exit(1)
    numAPIs.value += 1
    return response


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        print(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) + ': ' + str(response.text)[:300])
        sys.exit(1)


# This is the ST logout session management
#
# This is the ST /myself DELETE method
#
def stLogout(session, token):

    url = stUrl + 'myself'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall(session, 'DELETE', url, headers=headers)
    stExpect(response, 200, 'Logout')

    # Successful logout response
    # {
    #     "message" : "Logged out"
    # }
    print('Session Mgt Logged Out')
    return True


# Login to ST using session management, and return the csrfToken the server answers with
#
# This is the ST /myself POST method
#
def stLogin(basicAuth, session):

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth

    headers = {'Referer': referer,
               'Accept': 'application/json',
               'Authorization': authString}

    response = stCall(session, 'POST', url, headers=headers)
    stExpect(response, 200, 'Login')

    # Successful login response
    # {
    #     "message" : "Logged in"
    # }
    if response.json().get('message') != 'Logged in':
        print('The login did not answer "Logged in"')
        sys.exit(1)
    print('Session Login')
    # Present from the 20230525 release, and to be sent back on every write
    return response.headers.get('csrfToken')


def stProcessSites(session, csrftoken):

    entry = 0
    numberObjectsToFetchPerCall = 400
    keepLooping = True

    numberOfSSHSites = 0

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    while keepLooping:

        url = stUrl + 'sites?protocol=ssh&offset=' + str(entry) + '&limit=' + str(numberObjectsToFetchPerCall)

        response = stCall(session, 'GET', url, headers=headers)
        stExpect(response, 200, 'Reading the SSH sites')

        sites = response.json()

        returnCount = sites.get('resultSet', {}).get('returnCount', 0)

        if returnCount < numberObjectsToFetchPerCall:
            keepLooping = False

        for item in sites.get('result', []):
            numberOfSSHSites += 1
            kex = item.get('keyExchangeAlgorithms')
            account = item.get('account')
            siteId = item.get('id')
            if kex != masterKexAlg:
                print('Account ' + str(account) + ' has a site with ' + str(kex))
                print('It should have ' + str(masterKexAlg))
                #item.pop('metadata')
                item['keyExchangeAlgorithms'] = masterKexAlg

                updateSite(session, siteId, item, csrftoken)

        entry += numberObjectsToFetchPerCall

    return numberOfSSHSites


# PUT the whole site back with its change. True only when the server answered 204.
def updateSite(session, id, jsonin, csrftoken):

    url = stUrl + 'sites/' + str(id)

    if dryRun:
        print('   DRY RUN, would PUT site ' + str(id) + ' (' + str(jsonin.get('name')) + ')')
        return False

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    response = stCall(session, 'PUT', url, headers=headers, json=jsonin)
    if response.status_code != 204:
        print('The PUT of site ' + str(id) + ' answered ' + str(response.status_code) + ', not 204: ' +
              str(response.text)[:300])
        numFailed.value += 1
        return False
    numChanged.value += 1
    print('Successfully replaced Site with ID: ' + str(id))
    return True


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    #logFile = 'stUpdateSites.log'  # We won't use a logFile for this example
    stTimeout = 120  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'
    masterKexAlg = 'diffie-hellman-group14-sha256,diffie-hellman-group-exchange-sha256,curve25519-sha256@libssh.org,diffie-hellman-group15-sha512,diffie-hellman-group17-sha512,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512'

    # Report what would change, without changing anything. Run with this set to
    # True first, and read the output, before you let it write. --apply on the
    # command line sets it to False.
    dryRun = True

    arguments = sys.argv[1:]
    if '--apply' in arguments:
        dryRun = False
        arguments.remove('--apply')
    if arguments:
        print('Usage: python3 stReplaceSites.py [--apply]')
        sys.exit(2)

    # Read the configuration file. It is resolved relative to this script, so
    # the script can be run from any working directory.
    #
    stConfig = {}
    configFile = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'config')
    try:
        with open(configFile, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#') or '=' not in line:
                    continue
                key, value = line.split('=', 1)
                stConfig[key.strip()] = value.strip().strip('"')
    except IOError:
        print('I cannot find the configuration file: ' + configFile)
        print('Copy config.example to config and set the values for your environment.')
        sys.exit(1)

    stServer = stConfig.get('st_server', '')
    stPort = stConfig.get('st_port', '')
    stUser = stConfig.get('st_user', '')
    stPassword = stConfig.get('st_password', '')

    if not stServer or not stPort or not stUser or not stPassword:
        print('The configuration file must set st_server, st_port, st_user and st_password.')
        sys.exit(1)

    # Verify the server's certificate when st_ca_bundle (a file) or st_verify=yes is set
    stVerify = stConfig.get('st_ca_bundle', '') or stConfig.get('st_verify', 'no').lower() in ('yes', 'true', '1')

    #
    # Build the values the API calls need. The base64 Authorization value is
    # derived here, so there is no need to encode it by hand.
    #
    stUrl = 'https://' + stServer + ':' + stPort + '/api/v2.0/'
    basicAuth = base64.b64encode((stUser + ':' + stPassword).encode()).decode()

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    numAPIs = Value('i', 0)                  # counter to see how many APIS we sent
    numChanged = Value('i', 0)               # sites the server accepted
    numFailed = Value('i', 0)                # sites the server refused

    if dryRun:
        print('Running in DRY RUN mode, nothing will be changed. Add --apply to replace the algorithms.')
        print('')

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    numSites = stProcessSites(sessionMgt, csrftoken)
    print('I processed: ' + str(numSites) + ' SSH sites')
    # Completion Section

    stLogout(sessionMgt, csrftoken)
    print('Replaced: ' + str(numChanged.value) + ', refused: ' + str(numFailed.value))
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
    if numFailed.value:
        sys.exit(1)
