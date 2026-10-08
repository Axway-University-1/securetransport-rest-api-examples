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
# V2.00 Plamen Milenkov  08-Oct-2026  Shows what it would change and changes nothing unless
#                                     told to (--apply). CSRF compliant. The certificate is
#                                     found from the config or next to the script, not from
#                                     the current directory. Every failure exits 1.
# V1.10 ian Percival   22-Jul-2021 Converted from python2 to python3
# V1.00 Ian Percival   22-Feb-2021
#
# This script scans all template user accounts and updates a single field in that account
# (enrolledWithExternalPass, set to False)
#
# It uses Certificate based authentication, rather than Basic Auth
#
# APIs used - /myself ( ST login and logout )
#             /accounts ( GET and PATCH )
#
# Usage: python3 stUpdateAllAccounts.py [--apply]
#
#        Without --apply the script reads the template accounts and says what it would
#        send, and sends nothing. Start there.
#
# Risk: write - patches every template account on the server (with --apply)
#
# Notes:
# - It logs in with a TLS client certificate, so it needs the combined private key and
#   certificate, unencrypted, in one PEM file. That is st_client_cert in the config file,
#   or ST_API_client.pem next to this script when the key is not set. A relative
#   st_client_cert is read from the folder of the config file.
# - The server must accept it: Admin.ClientCertificateAuthentication is none by default,
#   and a certificate is then refused with 401 (see the gotchas).
# - Exit codes: 0 done, 1 anything failed (a patch that is refused included), 2 an
#   argument is not understood.
#
# Outputs:
#    A logile provides some information
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#
# All functions are defined first below this header.

import base64
import datetime
import json
import os
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning


#---------------------
# Supporting Functions
#---------------------

# Use a commin logFile in case running in batch etc
def writeLog(logString, severity):
    # This is the logfile for our python script
    print(logString)

    tstamp = datetime.datetime.now()
    inString = str(tstamp) + ' ' + severity + ' ' + logString + '\n'
    try:
        fHandle = open(logFile, 'a+')
        fHandle.write(inString)
        fHandle.close()
    except IOError:
        print('Problem writing to log')


# Send one request. Anything that keeps the call from completing is fatal: the script
# says what failed and exits 1. An HTTP status is not an exception, so the caller
# looks at it (see stExpect).
def stCall(session, method, url, **kwargs):
    try:
        response = getattr(session, method.lower())(url, verify=stVerify, timeout=stTimeout, **kwargs)
    except requests.exceptions.Timeout as et:
        writeLog('Timeout talking to ' + url + ': ' + str(et), 'FATAL')
        sys.exit(1)
    except requests.exceptions.ConnectionError as ec:
        writeLog('I cannot connect to ' + url + ': ' + str(ec), 'FATAL')
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        writeLog('The request to ' + url + ' failed: ' + str(e), 'FATAL')
        sys.exit(1)
    numAPIs.value += 1
    return response


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        writeLog(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) +
                 ': ' + str(response.text)[:300], 'FATAL')
        sys.exit(1)


def stProcessAllTemplates(stUrl, session, token):

    entry = 0
    numberToFetchEachTime = 200
    keepLooping = True

    numberOfUserAccounts = 0
    numberUpdated = 0

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    while keepLooping:

        url = stUrl + 'accounts?type=template&offset=' + str(entry) + '&limit=' + str(numberToFetchEachTime)

        response = stCall(session, 'GET', url, headers=headers)
        stExpect(response, 200, 'Reading the template accounts')

        jsonResponse = response.json()
        jsonAccounts = jsonResponse.get('result', [])

        if len(jsonAccounts) < numberToFetchEachTime:
            keepLooping = False

        for item in jsonAccounts:
            stUserAccount = item.get('name')
            extenalAuth = item.get('enrolledWithExternalPass')
            modify = True
            if extenalAuth is None:
                modify = False

            # Now perform the update
            if stUpdateAccount(stUrl, session, token, stUserAccount, modify):
                numberUpdated += 1

            numberOfUserAccounts += 1
        entry += numberToFetchEachTime

    infoText = 'Number of Template Accounts: ' + str(numberOfUserAccounts)
    writeLog(infoText, 'INFORMATION')
    return numberOfUserAccounts, numberUpdated


# Update a field in the account. False when the server refused it, or when dryRun said not to send it.
def stUpdateAccount(stUrl, session, token, accName, modify):

    url = stUrl + 'accounts/' + str(accName)

    # replace needs the field to be there already, add creates it
    if modify:
        jsonIn = [{'op': 'replace', 'path': '/enrolledWithExternalPass', 'value': False}]
    else:
        jsonIn = [{'op': 'add', 'path': '/enrolledWithExternalPass', 'value': False}]

    if dryRun:
        print('   DRY RUN, would send to ' + str(accName) + ': ' + json.dumps(jsonIn))
        return False

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    response = stCall(session, 'PATCH', url, headers=headers, json=jsonIn)
    if response.status_code != 204:
        writeLog('Update of account ' + str(accName) + ' answered ' + str(response.status_code) +
                 ': ' + str(response.text)[:300], 'ERROR')
        numFailed.value += 1
        return False
    writeLog('Updated account: ' + str(accName), 'INFORMATION')
    return True


# Login to ST using session management, with the client certificate on the session,
# and return the csrfToken the server answers with
#
# This is the ST api/v2.0/myself POST method
#
def stLogin(session):

    url = stUrl + 'myself'

    # If using Certiificate auth
    headers = {'Referer': referer,
               'Accept': 'application/json'}

    # If using Basic Auth
    #headers = {'Referer': referer,
    #          'Accept': 'application/json',
    #          'Authorization': 'Basic ' + basicAuth}

    response = stCall(session, 'POST', url, headers=headers)
    stExpect(response, 200, 'Login')

    # Successful login
    # {
    #     "message" : "Logged in"
    # }
    if response.json().get('message') != 'Logged in':
        writeLog('The login did not answer "Logged in"', 'FATAL')
        sys.exit(1)
    writeLog('Session Mgt Login', 'SUCCESS')
    # Present from the 20230525 release, and to be sent back on every write
    return response.headers.get('csrfToken')


# This is the ST logout session management
#
# This is the ST api/v2.0/myself DELETE method
#
def stLogout(session, token):

    url = stUrl + 'myself'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall(session, 'DELETE', url, headers=headers)
    stExpect(response, 200, 'Logout')

    # Successful logout
    # {
    #     "message" : "Logged out"
    # }
    writeLog('Logged Out', 'SUCCESS')
    return True


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#====================================================================================

if __name__ == "__main__":

    #--------------------------------------------------------------------------------
    # BEGIN Configuration Section
    #--------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120

    logFile = 'updateAccounts.log'

    referer = 'THIS_IS_A_RANDOM_TEXT'

    # Report what would change, without changing anything. Run with this set to
    # True first, and read the output, before you let it write. --apply on the
    # command line sets it to False.
    dryRun = True

    arguments = sys.argv[1:]
    if '--apply' in arguments:
        dryRun = False
        arguments.remove('--apply')
    if arguments:
        print('Usage: python3 stUpdateAllAccounts.py [--apply]')
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

    # The combined private key + certificate, unencrypted. Found from the config, or next to this script,
    # never from the folder the script happens to be started in.
    certificatePath = stConfig.get('st_client_cert', '') or 'ST_API_client.pem'
    if not os.path.isabs(certificatePath):
        base = os.path.dirname(configFile) if stConfig.get('st_client_cert') else os.path.dirname(os.path.abspath(__file__))
        certificatePath = os.path.normpath(os.path.join(base, certificatePath))

    #-------------------------------------------------------------------------------
    # END Configuration Section
    #-------------------------------------------------------------------------------

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent
    numFailed = Value('i', 0)                # patches the server refused

    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')

    if dryRun:
        print('Running in DRY RUN mode, nothing will be changed. Add --apply to change the accounts.')

    if not os.path.isfile(certificatePath):
        print('I cannot find the client certificate: ' + certificatePath)
        print('Put the combined private key and certificate there, or set st_client_cert in the config file.')
        sys.exit(1)

    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    sessionMgt = requests.Session()

    # If you wish to use Certificate authentication create an unencrypted private key + cert file
    sessionMgt.cert = certificatePath

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    csrftoken = stLogin(sessionMgt)

    # We won't use multiprocessing here as we are not doing too much
    # STEP 1 - loop through all template accounts
    numTemplates, numUpdated = stProcessAllTemplates(stUrl, sessionMgt, csrftoken)

    # Completion Section
    stLogout(sessionMgt, csrftoken)
    infoText = ('Completed Run. Template accounts: ' + str(numTemplates) + ', updated: ' + str(numUpdated) +
                ', refused: ' + str(numFailed.value) + '. Number of APIs issued: ' + str(numAPIs.value))
    writeLog(infoText, 'INFORMATION')
    if numFailed.value:
        sys.exit(1)
