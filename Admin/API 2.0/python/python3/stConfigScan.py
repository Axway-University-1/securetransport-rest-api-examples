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
# V3.00 Plamen Milenkov  08-Oct-2026  The baseline is a JSON file (it was a pickle, which runs
#                                     code when it is loaded), found next to the script or
#                                     where you say, and written readable by its owner only.
#                                     The comparison runs in both directions, so an option that
#                                     is gone from the live system is reported too. Every failure
#                                     exits 1, a bad argument exits 2.
# V2.00 Ian Percival   16-Jun-2023   Fix errors + csrf compliant
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default
#                                    for ST after and including the 20230525 release.
# V1.01 Ian Percival   20-Jul-2021   Python3 version
# V1.00 Ian Percival   28-Oct-2020
#
# This script will read all the system configuration settings from a system and will create a file
#  containing baseline data.  Subsequent runs will compare the live system with the saved file and
#  will identify any discrepancies.  Useful for checking after a PATCH, etc.
#
# APIs used - /myself ( ST login and logout )
#             /configurations/options  GET
#
# Usage: python3 stConfigScan.py MAKEBASELINE [BASELINE_FILE]
#        python3 stConfigScan.py COMPAREBASELINE [BASELINE_FILE]
#
#        BASELINE_FILE  where the baseline is written and read. When it is left out:
#                       st_config_baseline from the config file, or else a file named
#                       stConfig.baseline next to this script.
#
# Risk: read
#
# Notes:
# - It only reads the server. It does write the baseline file, as JSON, readable by its
#   owner only: the options of a server can hold secrets, so keep the file as private as
#   the server. *.baseline is in the .gitignore of this repository.
# - A COMPAREBASELINE reports what changed, what is new on the live system and what is in
#   the baseline but no longer on it. The differences are the output, not an error: the
#   exit code is 0 when it ran.
# - Exit codes: 0 done, 1 anything failed (no baseline to compare with included), 2 the
#   arguments are wrong.
#
# Outputs:
#    A logfile provides run time information
#    A file is used to store baseline config info
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


# ---------------------
# Supporting Functions
# ---------------------

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


def stGetConfig(session, token):

    windowSize = 100
    offset = 0
    getMore = True

    liveConfigs = {}

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    while getMore:

        url = stUrl + 'configurations/options?offset=' + str(offset) + '&limit=' + str(windowSize)

        response = stCall(session, 'GET', url, headers=headers)
        stExpect(response, 200, 'Reading the configuration options')

        configs = response.json()

        returnCount = configs.get('resultSet', {}).get('returnCount', 0)

        if returnCount < windowSize:
            getMore = False

        for item in configs.get('result', []):
            parameterName = item.get('name')
            parameterValue = item.get('values')
            if parameterName is None:
                continue
            liveConfigs[parameterName] = parameterValue

        offset += windowSize

    return liveConfigs


# Compare the baseline with the live configuration, in both directions.
# Returns (changed, new, gone): the names whose value differs, the names only on the
# live system, and the names only in the baseline.
def stCompare(baselineConfig, liveConfigs):

    changed = sorted(k for k in liveConfigs if k in baselineConfig and liveConfigs[k] != baselineConfig[k])
    new = sorted(k for k in liveConfigs if k not in baselineConfig)
    gone = sorted(k for k in baselineConfig if k not in liveConfigs)
    return changed, new, gone


# Write the baseline as JSON, readable by its owner only (the options can hold secrets).
def stWriteBaseline(path, configs):

    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(descriptor, 'w') as f:
            json.dump(configs, f, indent=1, sort_keys=True)
            f.write('\n')
        os.chmod(path, 0o600)       # a file that was there already keeps its old mode otherwise
    except (IOError, OSError) as e:
        writeLog('I cannot write the baseline ' + path + ': ' + str(e), 'FATAL')
        sys.exit(1)


# Read the baseline back. JSON, so reading it cannot run anything.
def stReadBaseline(path):

    try:
        with open(path, 'r') as f:
            baseline = json.load(f)
    except IOError:
        writeLog('I cannot read the baseline ' + path + '. Run MAKEBASELINE first.', 'FATAL')
        sys.exit(1)
    except ValueError:
        writeLog('The baseline ' + path + ' is not JSON. It was written by an older version of this script, '
                 'or by something else: run MAKEBASELINE again.', 'FATAL')
        sys.exit(1)
    if not isinstance(baseline, dict):
        writeLog('The baseline ' + path + ' does not hold a set of options.', 'FATAL')
        sys.exit(1)
    return baseline


# Login to ST using session management, and return the csrfToken the server answers with
#
# This is the ST api/v2.0/myself POST method
#
def stLogin(basicAuth, session):

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth
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
    writeLog('Session Login', 'INFORMATION')
    # Present from the 20230525 release, and to be sent back on every later call
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
    writeLog('Session Mgt Logged Out', 'SUCCESS')
    return True


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    usage = 'Usage: python3 stConfigScan.py MAKEBASELINE|COMPAREBASELINE [BASELINE_FILE]'

    if len(sys.argv) < 2 or len(sys.argv) > 3 or sys.argv[1] not in ('MAKEBASELINE', 'COMPAREBASELINE'):
        print('Please provide argument 1 - either MAKEBASELINE or COMPAREBASELINE')
        print(usage)
        sys.exit(2)
    mode = sys.argv[1]

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120

    logFile = 'checkConfig.log'

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

    # The baseline: the argument, else the config file, else next to this script
    baselineFile = (sys.argv[2] if len(sys.argv) > 2 else stConfig.get('st_config_baseline', '')
                    or os.path.join(os.path.dirname(os.path.abspath(__file__)), 'stConfig.baseline'))

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    t = 'Program called with argument ' + mode
    writeLog(t, 'INFORMATION')

    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')

    # A baseline to compare with has to be there before anything is asked of the server
    baselineConfig = None
    if mode == 'COMPAREBASELINE':
        baselineConfig = stReadBaseline(baselineFile)

    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    # Doing this saves a LOT of overhead and time.

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    csrftoken = stLogin(basicAuth, sessionMgt)

    # We won't use multiprocessing here as we are not doing too much
    # STEP 1 -
    # Read in the System Configs
    cConfigs = stGetConfig(sessionMgt, csrftoken)

    # See if we need to create a new baseline file containing all parameters.
    if mode == 'MAKEBASELINE':
        stWriteBaseline(baselineFile, cConfigs)
        writeLog('Wrote the baseline of ' + str(len(cConfigs)) + ' options to ' + baselineFile, 'INFORMATION')
    else:
        # cConfigs are the live system configs
        # compare these to what was there before, both ways
        changed, new, gone = stCompare(baselineConfig, cConfigs)
        for key in changed:
            t = key + ' has changed from ' + str(baselineConfig[key]) + '  to ' + str(cConfigs[key])
            writeLog(t, 'WARNING')
        for key in new:
            t = key + ' with value ' + str(cConfigs[key]) + ' does not exist in the baseline'
            writeLog(t, 'WARNING')
        for key in gone:
            t = key + ' with value ' + str(baselineConfig[key]) + ' is in the baseline but not on the live system'
            writeLog(t, 'WARNING')
        writeLog('Differences: ' + str(len(changed)) + ' changed, ' + str(len(new)) + ' new, ' +
                 str(len(gone)) + ' gone', 'INFORMATION')

    # Completion Section
    stLogout(sessionMgt, csrftoken)
    infoText = 'Completed Run. Number of APIs issued: ' + str(numAPIs.value)
    writeLog(infoText, 'INFORMATION')
