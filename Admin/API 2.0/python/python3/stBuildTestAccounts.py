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
# V3.00 Plamen Milenkov  08-Oct-2026  Shows what it would create and creates nothing unless told to
#                                     (--apply). The prefix and the number come from the command
#                                     line. The worker processes get what they need as arguments and
#                                     import what they use at the top of the file, so they also run
#                                     where a new process starts fresh (macOS, Windows, Python 3.14
#                                     on Linux). The queue ends with one None per worker instead of a
#                                     timeout that was never honoured. Every failure exits 1.
# V2.00 Ian Percival   16-Jun-2023   csrf compliant
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default
#                                    for ST after and including the 20230525 release.
# V1.00 Ian Percival   23-Nov-2021
#
# This script will Build a number of Test accounts on SecureTransport. They are named
# PREFIX0, PREFIX1 ... (ZZ0, ZZ1 ...), and stDeleteTestAccounts.py, which takes the same
# default prefix, deletes them again.
#
# It uses multiprocessing - to create 1000 accounts using 3 procs
#  takes around 6 mins.
#
# APIs used - /myself ( ST login and logout ) POST DELETE
#             /businessUnits  GET, POST
#             /accounts  POST
#
# Usage: python3 stBuildTestAccounts.py [--apply] [PREFIX [COUNT]]
#
#        PREFIX   the start of every account name. Default ZZ, at least 2 characters.
#        COUNT    how many accounts. Default 100.
#        --apply  create them. Without it the script says what it would create and
#                 sends nothing. Start there.
#
# Risk: write - creates a business unit and COUNT user accounts (with --apply)
#
# Notes:
# - Do not run it on a production ST. The accounts have a known password.
# - It first makes sure the business unit CatFoodCorporation is there: an existing one is
#   left as it is. stDeleteTestAccounts.py does not delete the business unit.
# - Exit codes: 0 done, 1 anything failed (an account that could not be created included),
#   2 the arguments are wrong.
#
# Outputs:
#    The number of accounts created and of APIs issued, on standard output.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

import base64
import datetime
import multiprocessing
import os
import sys

import requests

from multiprocessing import Process, Value, Queue
from requests.packages.urllib3.exceptions import InsecureRequestWarning
from urllib.parse import quote

# All functions are defined below
#
# A worker process is given everything it needs as arguments. `settings` holds the URL,
# the Referer, the timeout, the certificate check and the Authorization value: plain
# values, so they can be sent to a process that starts fresh. Nothing here reads a
# global that only the main block sets.


# A counter that every worker adds to: += on a shared Value is not atomic, so it is done holding the
# Value's own lock (without it, adds are lost when workers run at the same time)
def stCount(counter):
    with counter.get_lock():
        counter.value += 1


# Send one request. Anything that keeps the call from completing is fatal: the script
# says what failed and exits 1 (in a worker, that worker ends with 1). An HTTP status
# is not an exception, so the caller looks at it (see stExpect).
def stCall(session, method, url, settings, **kwargs):
    try:
        return getattr(session, method.lower())(url, verify=settings['verify'], timeout=settings['timeout'], **kwargs)
    except requests.exceptions.Timeout as et:
        print('Timeout talking to ' + url + ': ' + str(et))
    except requests.exceptions.ConnectionError as ec:
        print('I cannot connect to ' + url + ': ' + str(ec))
    except requests.exceptions.RequestException as e:
        print('The request to ' + url + ' failed: ' + str(e))
    sys.exit(1)


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        print(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) + ': ' + str(response.text)[:300])
        sys.exit(1)


# This is the ST logout session management
#
# This is the ST /myself DELETE method

def stLogout(session, token, settings, count):

    headers = {'Referer': settings['referer'],
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall(session, 'DELETE', settings['url'] + 'myself', settings, headers=headers)
    stCount(count)
    stExpect(response, 200, 'Logout')

    # Successful logout response
    # {
    #     "message" : "Logged out"
    # }
    return True


# Login to ST using session management, and return the csrfToken the server answers with
#
# This is the ST /myself POST method
#
def stLogin(session, settings, count):

    headers = {'Referer': settings['referer'],
               'Accept': 'application/json',
               'Authorization': 'Basic ' + settings['auth']}

    response = stCall(session, 'POST', settings['url'] + 'myself', settings, headers=headers)
    stCount(count)
    stExpect(response, 200, 'Login')

    # Successful login response
    # {
    #     "message" : "Logged in"
    # }
    if response.json().get('message') != 'Logged in':
        print('The login did not answer "Logged in"')
        sys.exit(1)
    # Present from the 20230525 release, and to be sent back on every write
    return response.headers.get('csrfToken')


# Make sure the business unit is there: an existing one is left alone, a missing one is created.
def stCreateBusinessUnit(session, settings, counter, token):

    url = settings['url'] + 'businessUnits'

    headers = {'Referer': settings['referer'],
               'csrfToken': token,
               'Accept': 'application/json',
               'Content-Type': 'application/json'
              }

    jsonIn = {
               'name': 'CatFoodCorporation',
               'baseFolder' : '/usrdata/CatFoodCo'
             }

    response = stCall(session, 'GET', url + '/' + quote(jsonIn['name']), settings, headers=headers)
    stCount(counter)
    if response.status_code == 200:
        print('The business unit ' + jsonIn['name'] + ' is there already, I leave it as it is')
        return True
    if response.status_code != 404:
        stExpect(response, 200, 'Looking for the business unit')

    response = stCall(session, 'POST', url, settings, json=jsonIn, headers=headers)
    stCount(counter)
    stExpect(response, 201, 'Creating the business unit')
    return True


# One worker process: log in once, create accounts from the queue until the None that
# ends it, log out.
def stCreateAccount(accNumQ, settings, count, failed, prefix):

    # This is created as a separate process - so no memory inheritance takes place
    # Parallel procs cannot use the same web socket so we need to create one per process
    if not settings['verify']:
        # turn off annoying messages
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(sessionMgt, settings, count)

    url = settings['url'] + 'accounts'

    headers = {
               'Referer': settings['referer'],     # This must be the same as the /myself use case
               'csrfToken': csrftoken,
               'Content-Type' :'application/json',
               'Accept': 'application/json'}

    while True:
        numAcc = accNumQ.get()
        if numAcc is None:
            # Nothing left to process
            break

        accName = prefix + str(numAcc)
        homeFolder = '/tmp/' + accName
        jsonIn = { "type" : "user",
                   "uid": "1000",
                   "gid": "1000",
                   "name": accName,
                   "homeFolder": homeFolder,
                   "user": { "name": accName,
                             "passwordCredentials": {"password": "axway"}
                           }
                  }

        response = stCall(sessionMgt, 'POST', url, settings, json=jsonIn, headers=headers)
        stCount(count)
        if response.status_code != 201:
            print('Problem Creating account ' + accName + ': ' + str(response.status_code))
            stCount(failed)
            continue

    stLogout(sessionMgt, csrftoken, settings, count)
    return


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    numberParallelProcesses = 3
    numberAccountsToCreate = 100
    namePrefix = 'ZZ'
    #logFile = 'updateConfig.log'  # We won't use a logFile for this example
    stTimeout = 60  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'

    # Show what would be created, without creating anything. Run with this set to
    # True first, and read the output, before you let it write. --apply on the
    # command line sets it to False.
    dryRun = True

    usage = 'Usage: python3 stBuildTestAccounts.py [--apply] [PREFIX [COUNT]]'
    arguments = sys.argv[1:]
    if '--apply' in arguments:
        dryRun = False
        arguments.remove('--apply')
    if len(arguments) > 2 or (len(arguments) > 1 and not arguments[1].isdigit()):
        print(usage)
        sys.exit(2)
    if len(arguments) > 0:
        namePrefix = arguments[0]
    if len(arguments) > 1:
        numberAccountsToCreate = int(arguments[1])
    if len(namePrefix) < 2 or '/' in namePrefix or numberAccountsToCreate < 1:
        print('The prefix is at least 2 characters, with no /, and the count at least 1.')
        print(usage)
        sys.exit(2)

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
    stUrl = 'https://' + stServer + ':' + stPort + '/api/v2.0/'
    basicAuth = base64.b64encode((stUser + ':' + stPassword).encode()).decode()

    # Everything a worker process needs, as plain values
    settings = {'url': stUrl, 'referer': referer, 'timeout': stTimeout,
                'verify': stVerify, 'auth': basicAuth}

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    names = [namePrefix + str(i) for i in range(numberAccountsToCreate)]

    if dryRun:
        print('DRY RUN, nothing will be created. Add --apply to create them.')
        print('Would make sure the business unit CatFoodCorporation is there, and create ' +
              str(len(names)) + ' user accounts:')
        for name in names[:5]:
            print('   ' + name)
        if len(names) > 5:
            print('   ... up to ' + names[-1])
        sys.exit(0)

    print('Running on a system with: ' + str(multiprocessing.cpu_count()) + ' CPUs')
    if os.name == 'posix' and hasattr(os, 'sched_getaffinity'):
        # sched_getaffinity is Linux only - os.name == 'posix' is also true on
        # macOS and BSD, where this raised AttributeError - confirmed directly.
        print('We can use: ' + str(os.sched_getaffinity(0)) + ' of these')
    outputString = 'Starting at: ' + str(datetime.datetime.now())
    print(outputString)

    # Counters of how many APIs get issued, and of the accounts that could not be created
    apiCount = Value('i', 0)
    numFailed = Value('i', 0)

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(sessionMgt, settings, apiCount)

    # Make sure the business unit that we'll be using with the test accounts is there
    stCreateBusinessUnit(sessionMgt, settings, apiCount, csrftoken)

    # Create a multiprocessing Queue which will be shared amongst our parallel procs.
    # One None per worker ends it: a worker takes the next number or its None, and waits
    # for nothing else.
    accNumQ = Queue()
    for i in range(numberAccountsToCreate):
        accNumQ.put(i)
    for x in range(numberParallelProcesses):
        accNumQ.put(None)

    processes = [Process(target=stCreateAccount, args=(accNumQ, settings, apiCount, numFailed, namePrefix))
                 for x in range(numberParallelProcesses)]
    for p in processes:
        p.start()

    for p in processes:
        p.join()

    # A worker that stopped early leaves numbers in the queue: do not wait for them to be read
    accNumQ.cancel_join_thread()
    accNumQ.close()

    stLogout(sessionMgt, csrftoken, settings, apiCount)
    workersFailed = len([p for p in processes if p.exitcode != 0])
    created = numberAccountsToCreate - numFailed.value
    print('I issued: ' + str(apiCount.value) + ' APIs')
    outputString = 'Ending at: ' + str(datetime.datetime.now())
    print(outputString)
    if numFailed.value or workersFailed:
        print('FAILED: ' + str(numFailed.value) + ' account(s) were refused, ' + str(workersFailed) +
              ' worker(s) stopped early. Some of the ' + str(numberAccountsToCreate) + ' were not created.')
        sys.exit(1)
    print('Created ' + str(created) + ' accounts, ' + names[0] + ' to ' + names[-1])
