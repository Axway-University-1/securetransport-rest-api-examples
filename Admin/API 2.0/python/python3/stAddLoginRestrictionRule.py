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
# V2.00 Plamen Milenkov  08-Oct-2026  CSRF compliant: the csrfToken of the login is sent
#                                     on the PATCH and the logout. Every failure exits 1.
# V1.00 Ian Percival     28-Mar-2022
#
# This script adds a new rule to an existing login restriction policy. The rule
# is the one in the configuration section below: change it to the rule you want.
#
# APIs used - /myself ( ST login and logout )
#             /loginRestrictionPolicies ( GET and PATCH )
#
# Usage: python3 stAddLoginRestrictionRule.py POLICY_NAME
#
#        POLICY_NAME  the name of the login restriction policy to add the rule to
#
# Risk: write - adds a rule to a login restriction policy, which can refuse logins if the policy is in use
#
# Outputs:
#    A logile provides some information
#
# Notes:
# - A rule is known by its name: if the policy already has a rule of that name the
#   script does nothing and exits 0, rather than replace it.
# - The rule goes in at the end, at the index that is the number of rules now there.
# - Exit codes: 0 done (or the rule was already there), 1 anything failed, 2 the
#   policy name is missing.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#
# All functions are defined first below this header.

import base64
import datetime
import os
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning
from urllib.parse import quote


# ---------------------
# Supporting Functions
# ---------------------

# Use a common logFile in case running in batch etc
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


# Read the policy, check it is there and does not have the rule yet, and PATCH the rule in.
# Returns True when the rule was added, False when it was already there.
def stPatchLoginRestriction(session, token, jsonIn, loginRest):

    url = stUrl + 'loginRestrictionPolicies/' + quote(loginRest)

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall(session, 'GET', url, headers=headers)
    if response.status_code == 404:
        writeLog('I cannot Find the Login Restriction named: ' + loginRest, 'FATAL')
        sys.exit(1)
    stExpect(response, 200, 'Reading the login restriction')

    jsonResponse = response.json()
    if jsonResponse.get('name') != loginRest:
        writeLog('I cannot Find the Login Restriction named: ' + loginRest, 'FATAL')
        sys.exit(1)

    rules = jsonResponse.get('rules') or []
    for item in rules:
        if item.get('name') == jsonIn[0]['value']['name']:
            writeLog('A rule already exists with the provided name', 'INFORMATION')
            return False

    # Now that we have identified how many rules are present - we can perform our update and patch
    # the login Restriction. An index equal to the number of rules adds the rule at the end.
    jsonIn[0]['path'] = '/rules/' + str(len(rules))

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    response = stCall(session, 'PATCH', url, headers=headers, json=jsonIn)
    stExpect(response, 204, 'Adding the rule')
    writeLog('Added the rule ' + jsonIn[0]['value']['name'] + ' to ' + loginRest, 'SUCCESS')
    return True


# Login to ST using session management, and return the csrfToken the server answers with
#
# This is the ST api/v2.0/myself POST method
#
def stLogin(basicAuth, session):

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth
    # If using Certiificate auth
    #headers = {'Referer': referer,
    #           'Accept': 'application/json'}

    headers = {'Referer': referer,
               'Accept': 'application/json',
               'Authorization': authString}

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


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    try:
        loginRest = sys.argv[1]
    except IndexError:
        print('Please provide argument 1 - The name of your login Restriction')
        print('Usage: python3 stAddLoginRestrictionRule.py POLICY_NAME')
        sys.exit(2)

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120
    logFile = 'updateLoginRestrictions.log'
    referer = 'THIS_IS_A_RANDOM_TEXT'

    # please modify the json "value" key  here to match your new rule
    jsonIn = [
        {
            "op": "add",
            "path": "/rules/",
            "value": {"name": "sessions fewer than 4",
                      "isEnabled": True,
                      "type": "ALLOW",
                      "clientAddress": "*",
                      "expression": "${currentSessions <= 3}",
                      "description": "Only allow if less than 4 sessions"
                      }
        }
    ]

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

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    sessionMgt = requests.Session()

    csrftoken = stLogin(basicAuth, sessionMgt)

    # STEP 1
    stPatchLoginRestriction(sessionMgt, csrftoken, jsonIn, loginRest)

    # Completion Section
    stLogout(sessionMgt, csrftoken)
    infoText = 'Completed Run. Number of APIs issued: ' + str(numAPIs.value)
    writeLog(infoText, 'INFORMATION')
