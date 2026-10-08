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
# V2.00 Plamen Milenkov  08-Oct-2026  CSRF compliant: the logout sends the csrfToken. Every
#                                     failure exits 1, a missing or bad date exits 2.
# V1.01 ian Percival   20-Jun-2023 Fix typo on first line!
# V1.00 Ian Percival   21-Jul-2022
#
# This script will output all accounts created after an input date...
#
# APIs used - /myself ( ST login and logout ) POST DELETE
#             /accounts  GET
#
# Usage: python3 stGetAccountsAfterDate.py YYYY-MM-DD
#
# Risk: read
#
# Notes:
# - Only user accounts are listed (type=user). An account with no creation date is skipped.
# - Exit codes: 0 done, 1 anything failed, 2 the date is missing or not YYYY-MM-DD.
#
# Outputs:
#    The accounts, with their creation date, on standard output.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

import base64
import datetime
import os
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# All functions are defined below


def writeLog(logString, severity):
    # No log file in this example: the message goes to the screen.
    print(severity + ' ' + logString)


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
    apiCount.value += 1
    return response


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        writeLog(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) +
                 ': ' + str(response.text)[:300], 'FATAL')
        sys.exit(1)


# This is the ST logout session management
#
# This is the ST /myself DELETE method
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
    print('\nSession Mgt Logged Out')
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
        writeLog('The login did not answer "Logged in"', 'FATAL')
        sys.exit(1)
    print('Session Mgt Login using /myself: SUCCESS')
    # Present from the 20230525 release, and to be sent back on every later call
    return response.headers.get('csrfToken')


def stGetAccounts(stUrl, session, token, count, fromDate):

    entry = 0
    numberToFetchEachTime = 200
    keepLooping = True

    numberOfUserAccounts = 0

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    while keepLooping:

        url = stUrl + 'accounts?type=user&offset=' + str(entry) + '&limit=' + str(numberToFetchEachTime)

        response = stCall(session, 'GET', url, headers=headers)
        stExpect(response, 200, 'Reading the accounts')

        jsonAccounts = response.json().get('result', [])

        if len(jsonAccounts) < numberToFetchEachTime:
            keepLooping = False

        for item in jsonAccounts:
            stUserAccount = item.get('name')
            createDate = item.get('accountCreationDate')
            if createDate is None:
                continue
            createDate = datetime.datetime.fromtimestamp(float(createDate) / 1000.)

            if createDate < fromDate:
                continue
            print(stUserAccount, ' has creation date: ', createDate)
            numberOfUserAccounts += 1

        entry += numberToFetchEachTime

    print('There were: ', numberOfUserAccounts, ' created in this time period')
    return numberOfUserAccounts


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    try:
        fromDate = datetime.datetime.strptime(sys.argv[1], "%Y-%m-%d")
    except IndexError:
        print('Please provide argument 1 to list all accounts created after date X in format YYYY-MM-DD')
        sys.exit(2)
    except ValueError:
        print('The date must be in format YYYY-MM-DD, not ' + sys.argv[1])
        sys.exit(2)

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 60  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'

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

    outputString = 'Starting at: ' + str(datetime.datetime.now())
    print(outputString)

    # Counter of how many APIs get issued
    apiCount = Value('i', 0)

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    stGetAccounts(stUrl, sessionMgt, csrftoken, apiCount, fromDate)

    stLogout(sessionMgt, csrftoken)
    print('I issued: ' + str(apiCount.value) + ' APIs')
    outputString = 'Ending at: ' + str(datetime.datetime.now())
    print(outputString)
