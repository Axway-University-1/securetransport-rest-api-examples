#! /usr/bin/python3
#
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
# V3.00 Plamen Milenkov  08-Oct-2026  Safe by default: it lists the accounts whose name STARTS
#                                     with the prefix and deletes nothing unless told to
#                                     (--apply). Only user accounts are listed (type=user: the
#                                     accountType= it used before is not a parameter of the
#                                     API, and the lab answered every account whatever its
#                                     value). The status of every DELETE is checked and only a
#                                     204 counts. The worker processes get what they need as
#                                     arguments, as in stBuildTestAccounts.py. Every failure
#                                     exits 1.
# V2.00 Ian Percival   16-Jun-2023   Fix errors + csrf compliant
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default
#                                    for ST after and including the 20230525 release.
# V1.00 Ian Percival   30-Nov-2021
#
# This script will Delete a number of Test accounts on SecureTransport: the user accounts
# whose name starts with a prefix (ZZ by default, which is what stBuildTestAccounts.py makes).
# WARNING - DO NOT RUN in your production ST!
#
# It uses multiprocessing - so can delete a LOT of accounts fairly quickly....
#
# APIs used - /myself ( ST login and logout ) POST DELETE
#             /accounts  GET, DELETE
#
# Usage: python3 stDeleteTestAccounts.py [--apply] [PREFIX]
#
#        PREFIX   delete the user accounts whose name starts with this, case sensitive.
#                 Default ZZ, at least 2 characters.
#        --apply  delete them. Without it the script lists what it WOULD delete and
#                 deletes nothing. Start there, and read the list.
#
# Risk: write - deletes every user account whose name starts with the prefix (with --apply)
#
# Notes:
# - The match is "starts with", not "contains": an account named myZZ or zz1 is left alone.
#   Template and service accounts are never listed, whatever they are called.
# - Confirmed directly (5.5-20260924): GET /accounts?accountType=user answers every account,
#   and so does accountType=template and accountType=nonsense: it is ignored. The filter is
#   type=, whose unknown value is a 400. An earlier version of this script used accountType=.
# - Deleting an account does not delete the files of its home folder.
# - Exit codes: 0 done (nothing to delete included), 1 anything failed (a delete that did not
#   answer 204 included), 2 the arguments are wrong.
#
# Outputs:
#    The accounts that match, and how many were deleted.
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


# The names of the user accounts that start with the prefix. Read only.
def stGetAccounts(session, token, settings, count, prefix):

    entry = 0
    numberToFetchEachTime = 200
    keepLooping = True
    headers = {'Referer': settings['referer'],
               'csrfToken': token,
               'Accept': 'application/json'}
    matching = []
    numberSeen = 0

    while keepLooping:
        # type= is the filter of the reference: accountType= is not a parameter and is ignored
        url = settings['url'] + 'accounts?type=user&offset=' + str(entry) + '&limit=' + str(numberToFetchEachTime)

        response = stCall(session, 'GET', url, settings, headers=headers)
        stCount(count)
        stExpect(response, 200, 'Reading the accounts')

        jsonAccounts = response.json().get('result', [])

        if len(jsonAccounts) < numberToFetchEachTime:
            keepLooping = False

        for item in jsonAccounts:
            numberSeen += 1
            stUserAccountName = item.get('name')
            # The server filters by type; this is a second look, in case a server does not
            if item.get('type') not in (None, 'user') or not stUserAccountName:
                continue
            if stUserAccountName.startswith(prefix):
                matching.append(stUserAccountName)

        entry += numberToFetchEachTime

    return matching, numberSeen


# One worker process: log in once, delete the accounts from the queue until the None that
# ends it, log out. Only a 204 counts as a deleted account.
def stDeleteAccount(accNumQ, settings, count, deleted, failed):

    # This is created as a separate process - so no memory inheritance takes place
    if not settings['verify']:
        # turn off annoying messages
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(sessionMgt, settings, count)

    headers = {'Referer': settings['referer'],       # This must be the same as the /myself use case
               'csrfToken': csrftoken,
               'Accept': 'application/json'}
    while True:
        accName = accNumQ.get()
        if accName is None:
            # Nothing left to process
            break

        url = settings['url'] + 'accounts/' + quote(accName)
        response = stCall(sessionMgt, 'DELETE', url, settings, headers=headers)
        stCount(count)
        if response.status_code != 204:
            print('Could not delete ' + accName + ': ' + str(response.status_code) + ' ' + str(response.text)[:200])
            stCount(failed)
            continue
        stCount(deleted)

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
    #logFile = 'updateConfig.log'  # We won't use a logFile for this example
    stTimeout = 60  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'
    namePrefix = 'ZZ'  # if an ST user account name STARTS with this - then delete it! (the default of stBuildTestAccounts.py)

    # List what would be deleted, without deleting anything. Run with this set to
    # True first, and read the list, before you let it delete. --apply on the
    # command line sets it to False.
    dryRun = True

    usage = 'Usage: python3 stDeleteTestAccounts.py [--apply] [PREFIX]'
    arguments = sys.argv[1:]
    if '--apply' in arguments:
        dryRun = False
        arguments.remove('--apply')
    if len(arguments) > 1:
        print(usage)
        sys.exit(2)
    if len(arguments) == 1:
        namePrefix = arguments[0]
    if len(namePrefix) < 2:
        print('The prefix is at least 2 characters: a shorter one would match too many accounts.')
        print(usage)
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

    # Everything a worker process needs, as plain values
    settings = {'url': stUrl, 'referer': referer, 'timeout': stTimeout,
                'verify': stVerify, 'auth': basicAuth}

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    print('Running on a system with: ' + str(multiprocessing.cpu_count()) + ' CPUs')
    if os.name == 'posix' and hasattr(os, 'sched_getaffinity'):
        # sched_getaffinity is Linux only - os.name == 'posix' is also true on
        # macOS and BSD, where this raised AttributeError - confirmed directly.
        print('We can use: ' + str(os.sched_getaffinity(0)) + ' of these')
    outputString = 'Starting at: ' + str(datetime.datetime.now())
    print(outputString)

    # Counters of how many APIs get issued, and of the accounts deleted and not
    apiCount = Value('i', 0)
    numDeleted = Value('i', 0)
    numFailed = Value('i', 0)

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(sessionMgt, settings, apiCount)

    # Build the list of the accounts that we wish to delete, in a single threaded way
    matching, numberSeen = stGetAccounts(sessionMgt, csrftoken, settings, apiCount, namePrefix)

    print('')
    print(str(len(matching)) + ' of ' + str(numberSeen) + ' user accounts have a name that starts with ' + namePrefix + ':')
    for name in matching:
        print('   ' + name)
    print('')

    workersFailed = 0
    if dryRun:
        print('DRY RUN, nothing was deleted. Add --apply to delete the ' + str(len(matching)) + ' accounts listed.')
    elif matching:
        # Create a multiprocessing Queue which will be shared amongst our parallel procs.
        # One None per worker ends it: a worker takes the next name or its None, and waits
        # for nothing else.
        workers = min(numberParallelProcesses, len(matching))
        accNumQ = Queue()
        for name in matching:
            accNumQ.put(name)
        for x in range(workers):
            accNumQ.put(None)

        processes = [Process(target=stDeleteAccount, args=(accNumQ, settings, apiCount, numDeleted, numFailed))
                     for x in range(workers)]
        for p in processes:
            p.start()

        for p in processes:
            p.join()

        # A worker that stopped early leaves names in the queue: do not wait for them to be read
        accNumQ.cancel_join_thread()
        accNumQ.close()
        workersFailed = len([p for p in processes if p.exitcode != 0])

    stLogout(sessionMgt, csrftoken, settings, apiCount)
    print('I issued: ' + str(apiCount.value) + ' APIs')
    outputString = 'Ending at: ' + str(datetime.datetime.now())
    print(outputString)
    if not dryRun:
        print('Deleted ' + str(numDeleted.value) + ' of ' + str(len(matching)) + ' accounts')
    if numFailed.value or workersFailed or (not dryRun and numDeleted.value != len(matching)):
        print('FAILED: ' + str(numFailed.value) + ' delete(s) were refused, ' + str(workersFailed) + ' worker(s) stopped early.')
        sys.exit(1)
