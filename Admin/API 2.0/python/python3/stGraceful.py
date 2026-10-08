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
# V2.00 Plamen Milenkov  08-Oct-2026  Made safe to read and to run: it stops nothing
#                                     without --yes, checks every status, sends the
#                                     csrfToken, stops a daemon by the daemon= the
#                                     reference documents, and every wait is bounded.
# V1.00 Ian Percival     18-Oct-2021
#
# THIS STOPS THE SERVER. It drains a SecureTransport server, and the edge server of a
# core plus edge pair, ready for maintenance: it stops the FolderMonitor and Scheduler
# cluster services, every protocol daemon (ftp, http, ssh, as2 and pesit), and
# finally the Transaction Manager. Every protocol is refused until someone starts
# the daemons again, and THE API HAS NO WAY TO START THE TRANSACTION MANAGER AGAIN:
# it takes a restart of the server's own service. A graceful stop with a timeout
# also keeps running on the server after this script has gone, so never kill the
# script half way. Run it on a lab system first, never on one you cannot restart.
#
# Order, and what makes it stop before anything cannot be undone:
#
#   1. FolderMonitor and Scheduler are stopped, and the script waits for them.
#   2. Each protocol daemon that has a running server is stopped gracefully: the
#      connections in progress get SECONDS to finish.
#   3. The script waits, a bounded time, until no server of any protocol is active.
#   4. Only when every one of them is down is the Transaction Manager stopped.
#
# Any failure on the way (a status that is not 200, a service or daemon still running
# when the wait is over, a server that cannot be reached) ends the script with exit
# code 1 BEFORE the Transaction Manager is touched, and says what is still running.
#
# APIs used - /myself ( ST login and logout )
#             /clusterServices             GET
#             /clusterServices/operations  POST
#             /servers                     GET
#             /daemons/operations          POST
#             /transactionManager          GET
#             /transactionManager/operations  POST
#
# Usage: python3 stGraceful.py SECONDS --yes
#
#        SECONDS  how long the connections in progress may take to finish, a whole
#                 number. The script waits up to SECONDS plus a minute for the
#                 daemons to be down.
#        --yes    the confirmation. There is no default and no other way to give it:
#                 without it the script sends nothing and exits 2.
#
# Risk: disruptive - stops the cluster services, every protocol daemon and the Transaction Manager, which cannot be started again through the API
#
# Notes:
# - The edge server is the host in the optional st_edge_server key of the config
#   file. When it is not set, or is the same as st_server, only one server is drained.
# - Exit codes: 0 when everything was stopped, 1 when anything failed (the Transaction
#   Manager is only stopped after every daemon is down), 2 when the arguments are wrong
#   or --yes is missing (nothing was sent).
# - A daemon is stopped with the daemon=<protocol> of the reference. An earlier version
#   sent serverName=, which the reference does not give that endpoint.
# - Not run on the lab by the people who made it safe: a stop cannot be taken back (see
#   tests/integration/checks/manual.graceful_scripts.py for the outage an earlier run
#   caused). It is tested offline, against a fake server, in tests/checks.
# - Confirmed directly, a read: GET /servers?fields=isActive answers
#   {"protocol": ..., "isActive": ...} for each server. The protocol comes back
#   whether or not fields= asks for it, as the type does for an account.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

import base64
import datetime
import os
import sys
import time

import requests

from requests.packages.urllib3.exceptions import InsecureRequestWarning
from urllib.parse import quote

from multiprocessing import Value


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
# looks at it (see stExpect). Only the logout, which comes after the work is done, may
# ask for fatal=False and get None back instead of the exit.
def stCall(session, method, url, fatal=True, **kwargs):
    try:
        response = getattr(session, method.lower())(url, verify=stVerify, timeout=stTimeout, **kwargs)
    except requests.exceptions.Timeout as et:
        problem = 'Timeout talking to ' + url + ': ' + str(et)
    except requests.exceptions.ConnectionError as ec:
        problem = 'I cannot connect to ' + url + ': ' + str(ec)
    except requests.exceptions.RequestException as e:
        problem = 'The request to ' + url + ' failed: ' + str(e)
    else:
        numAPIs.value += 1
        return response
    writeLog(problem, 'FATAL' if fatal else 'WARNING')
    if fatal:
        sys.exit(1)
    return None


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        writeLog(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) +
                 ': ' + str(response.text)[:300], 'FATAL')
        sys.exit(1)


# A GET whose answer is JSON
def stGetJson(session, stUrl, token, path, what):
    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}
    response = stCall(session, 'GET', stUrl + path, headers=headers)
    stExpect(response, 200, what)
    try:
        return response.json()
    except ValueError:
        writeLog(what + ' did not answer JSON', 'FATAL')
        sys.exit(1)


# A POST with no body: an operation
def stPostOperation(session, stUrl, token, path, what):
    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}
    response = stCall(session, 'POST', stUrl + path, headers=headers)
    stExpect(response, 200, what)
    return response


def getTransactionManagerStatus(session, stUrl, token):

    jsonResponse = stGetJson(session, stUrl, token, 'transactionManager', 'Get TM status')
    writeLog('Get TM status', 'SUCCESS')
    return 'Running' in str(jsonResponse.get('status'))


def stopTransactionManager(session, stUrl, token, gtime):

    stPostOperation(session, stUrl, token,
                    'transactionManager/operations?operation=stop&graceful=true&timeout=' + str(gtime),
                    'Stop Transaction Manager')
    writeLog('Stop Transaction Manager', 'SUCCESS')


# folder monitor and scheduler
def getClusterServiceStatus(session, stUrl, token, service):

    jsonResponse = stGetJson(session, stUrl, token, 'clusterServices?serviceName=' + service,
                             'Get Cluster Service ' + service)
    return 'Running' in str(jsonResponse.get('status'))


def stopClusterServices(session, stUrl, token, service):

    stPostOperation(session, stUrl, token,
                    'clusterServices/operations?operation=stop&serviceName=' + service,
                    'Stop Cluster Service ' + service)
    writeLog('Stop Cluster Service ' + service, 'SUCCESS')


# True while any server of this protocol is active.
#
# fields=isActive keeps the answer small. The server still names the protocol of each
# server, so the loop below does not rely on it being asked for.
def getServerDaemonsStatus(session, stUrl, token, protocol):

    jsonResponse = stGetJson(session, stUrl, token, 'servers?fields=isActive&protocol=' + protocol,
                             'Get the ' + protocol + ' servers')

    daemonRunning = False
    for item in jsonResponse.get('result', []):
        if item.get('isActive'):
            print(str(item.get('protocol', protocol)) + ' is still running')
            daemonRunning = True

    return daemonRunning


# Stop the daemon of one protocol: the daemon= of /daemons/operations. Its result says,
# daemon by daemon, whether it worked, whatever the status code.
def stopDaemon(session, stUrl, token, protocol, gracefultime):

    response = stPostOperation(session, stUrl, token,
                               'daemons/operations?operation=stop&daemon=' + quote(protocol) +
                               '&graceful=true&timeout=' + str(gracefultime),
                               'Stop the ' + protocol + ' daemon')
    try:
        results = response.json().get('daemonOperationResults', [])
    except ValueError:
        results = []
    for result in results:
        if result.get('isSuccessful') is False:
            writeLog('Stop of the ' + protocol + ' daemon failed: ' + str(result.get('message')), 'FATAL')
            sys.exit(1)
    writeLog('Stop the ' + protocol + ' daemon', 'SUCCESS')


# Stop the cluster services, and wait for them, for at most maxWait seconds in all.
# Returns the services that are still running when the time is up.
def stDrainClusterServices(session, stUrl, token, services, maxWait):

    running = [service for service in services if getClusterServiceStatus(session, stUrl, token, service)]
    for service in running:
        print('A ' + service + ' is still running')
        stopClusterServices(session, stUrl, token, service)

    deadline = time.monotonic() + maxWait
    while True:
        running = [service for service in running if getClusterServiceStatus(session, stUrl, token, service)]
        if not running:
            return []
        if time.monotonic() >= deadline:
            return running
        time.sleep(pollSeconds)


# Wait until no server of any protocol is active, for at most maxWait seconds.
#
# targets is a list of (label, session, url, token). Each protocol of each target is
# looked at once per round and dropped from the list as soon as it is down, and the
# script sleeps once per round, not once per protocol. Returns what is still running
# when the time is up, as "label protocol".
def stWaitForDaemons(targets, protocols, maxWait):

    pending = [(label, session, stUrl, token, protocol)
               for (label, session, stUrl, token) in targets for protocol in protocols]
    deadline = time.monotonic() + maxWait

    while True:
        pending = [item for item in pending if getServerDaemonsStatus(item[1], item[2], item[3], item[4])]
        if not pending:
            return []
        if time.monotonic() >= deadline:
            return [item[0] + ' ' + item[4] for item in pending]
        time.sleep(pollSeconds)


# Login to ST using session management, and return the csrfToken it answers with
#
# This is the ST api/v2.0/myself POST method
#
def stLogin(basicAuth, session, stUrl):

    url = stUrl + 'myself'
    authString = 'Basic ' + basicAuth

    # If using Certiificate auth
    #headers = {'Referer': referer,
    #          'Accept': 'application/json'}

    headers = {'Referer': referer,
               'Accept': 'application/json',
               'Authorization': authString}

    response = stCall(session, 'POST', url, headers=headers)
    if response.status_code != 200:
        writeLog('Cannot login to ' + stUrl + ', the status is ' + str(response.status_code), 'FATAL')
        sys.exit(1)

    # Successful login
    # {
    #     "message" : "Logged in"
    # }
    try:
        message = response.json().get('message')
    except ValueError:
        message = None
    if message != 'Logged in':
        writeLog('Login to ' + stUrl + ' did not answer "Logged in"', 'FATAL')
        sys.exit(1)

    writeLog('Session Mgt Login', 'SUCCESS')
    # Present from the 20230525 release. Every later call sends it back.
    return response.headers.get('csrfToken')


# This is the ST logout session management
#
# This is the ST api/v2.0/myself DELETE method
#
# It comes after the Transaction Manager was stopped, when the server may already be on
# its way down, so a logout that fails is a warning, not a reason to report the run failed.
def stLogout(session, stUrl, token):

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}
    response = stCall(session, 'DELETE', stUrl + 'myself', fatal=False, headers=headers)
    if response is None or response.status_code != 200:
        writeLog('The logout from ' + stUrl + ' did not work; everything was stopped all the same', 'WARNING')
        return False

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

    usage = 'Usage: python3 stGraceful.py SECONDS --yes'

    # The arguments come first: nothing is read, and nothing is sent, until they are right.
    arguments = [a for a in sys.argv[1:] if a != '--yes']
    confirmed = '--yes' in sys.argv[1:]
    if len(arguments) != 1 or not arguments[0].isdigit():
        print('Please provide argument 1 - the number of seconds the connections in progress may take')
        print(usage)
        sys.exit(2)
    gtime = arguments[0]
    if not confirmed:
        print('THIS STOPS THE SERVER: the cluster services, every protocol daemon and the')
        print('Transaction Manager, which the API cannot start again.')
        print('Nothing was sent. To go on, say so: python3 stGraceful.py ' + gtime + ' --yes')
        sys.exit(2)

    #--------------------------------------------------------------------------------
    # BEGIN Configuration Section
    #--------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120
    logFile = 'my.log'
    referer = 'THIS_IS_A_RANDOM_TEXT'

    # Seconds between two looks at what is still running, and how long the cluster
    # services get to stop. The daemons get the number of seconds given on the command
    # line, plus the margin.
    pollSeconds = 5
    serviceWaitSeconds = 120
    daemonMarginSeconds = 60

    #
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
    # This example can talk to a core server and an edge server. The edge host
    # comes from the optional st_edge_server key. Without it there is one server.
    stEdgeServer = stConfig.get('st_edge_server', '') or stServer

    stUrlCore = 'https://' + stServer + ':' + stPort + '/api/v2.0/'
    stUrlEdge = 'https://' + stEdgeServer + ':' + stPort + '/api/v2.0/'
    basicAuth = base64.b64encode((stUser + ':' + stPassword).encode()).decode()

    #-------------------------------------------------------------------------------
    # END Configuration Section
    #-------------------------------------------------------------------------------

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    sessions = [('Core', requests.Session(), stUrlCore)]
    if stEdgeServer != stServer:
        sessions.append(('Edge', requests.Session(), stUrlEdge))

    targets = []
    for label, session, url in sessions:
        token = stLogin(basicAuth, session, url)
        targets.append((label, session, url, token))

    coreLabel, coreSession, coreUrl, coreToken = targets[0]

    # 1. The cluster services of the core server
    left = stDrainClusterServices(coreSession, coreUrl, coreToken, ['FolderMonitor', 'Scheduler'],
                                  serviceWaitSeconds)
    if left:
        writeLog('Still running after ' + str(serviceWaitSeconds) + ' seconds: ' + ', '.join(left) +
                 '. Nothing else was stopped.', 'FATAL')
        sys.exit(1)

    # 2. The daemons, protocol by protocol, on each server
    protocols = ['http', 'pesit', 'ssh', 'ftp', 'as2']
    for label, session, url, token in targets:
        for protocol in protocols:
            if getServerDaemonsStatus(session, url, token, protocol):
                stopDaemon(session, url, token, protocol, gtime)

    # 3. Wait until no server is active, and give up at the deadline
    left = stWaitForDaemons(targets, protocols, int(gtime) + daemonMarginSeconds)
    if left:
        writeLog('Still running after ' + str(int(gtime) + daemonMarginSeconds) + ' seconds: ' +
                 ', '.join(left) + '. The Transaction Manager was NOT stopped.', 'FATAL')
        sys.exit(1)

    # 4. Only now the Transaction Manager, which cannot be started again through the API
    if getTransactionManagerStatus(coreSession, coreUrl, coreToken):
        print('The TM is still running')
        stopTransactionManager(coreSession, coreUrl, coreToken, gtime)

    # Completion Section
    for label, session, url, token in targets:
        stLogout(session, url, token)

    infoText = 'Completed Run. Number of APIs issued: ' + str(numAPIs.value)
    writeLog(infoText, 'INFORMATION')
