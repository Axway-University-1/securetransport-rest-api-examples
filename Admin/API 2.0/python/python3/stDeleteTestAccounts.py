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
# V2.00 Ian Percival   16-Jun-2023   Fix errors + csrf compliant 
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default 
#                                    for ST after and including the 20230525 release.
# V1.00 Ian Percival   30-Nov-2021
#
# This script will Delete a number of Test accounts on SecureTransport
# WARNING - DO NOT RUN in your production ST!
#
# It uses multiprocessing - so can delete a LOT of accounts fairly quickly....
#
# APIs used - /myself ( ST login and logout ) POST DELETE
#             /accounts  GET, DELETE
#
# Usage: python3
#
# Outputs:
#
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

# All functions are defined below


# This is the ST logout session management
#
# This is the ST /myself DELETE method

def stLogout(session, token):

    url = stUrl + 'myself'

    headers =  {'Referer': referer,
                'csrfToken': token,
                'Accept': 'application/json'}
    try:
        response = session.delete(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        print('I cannot connect to ' + stUrl + ' ' + str(ec))
        sys.exit(1)
    except requests.exceptions.HTTPError as eh:
        print('HTTP Error')
        sys.exit(1)
    except requests.exceptions.Timeout as et:
        print('Timeout Error:' + str(et))
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print('Unknown Error: ' + str(e))
        sys.exit(1)
    else:
        apiCount.value += 1
        print('\nSession Mgt Logged Out')
        return True

        # Successful logout response

        # {
        #     "message" : "Logged out"
        # }


# Login to ST using session management
#
# This is the ST /myself POST method
#
def stLogin(basicAuth, session):

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth

    headers = {'Referer': referer,
               'Accept': 'application/json',
               'Authorization': authString}

    try:
        response = session.post(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        print('I cannot connect to ' + stUrl + ' ' + str(ec))
        sys.exit(1)
    except requests.exceptions.HTTPError as eh:
        print('HTTP Error ' + str(eh))
        sys.exit(1)
    except requests.exceptions.Timeout as et:
        print('Timeout Error:' + str(et))
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print('Unknown Error ' + str(e))
        sys.exit(1)
    else:
        apiCount.value += 1
        if response.status_code != 200:
            print("Cannot login ", response.status_code)
            sys.exit(1)
        jsonResponse = response.json()
        csrftoken = response.headers.get('csrfToken')
        message = jsonResponse.get("message")
        if 'Logged in' == message:
            print('Session Login', 'INFORMATION')
            return csrftoken
        else:
            print("Login Failure ",response.status_code)
            sys.exit(1)

        # Successful login response

        # {
        #     "message" : "Logged in"
        # }


def stGetAccounts(accNumQ):

    entry = 0
    numberToFetchEachTime = 200
    keepLooping = True
    headers = {'Referer': referer,
               'Accept': 'application/json'}

    while keepLooping:
        url = stUrl + 'accounts?accountType=user&offset=' + str(entry) + '&limit=' + str(numberToFetchEachTime)

        try:
            response = sessionMgt.get(url, headers=headers, verify=False, timeout=stTimeout)
        except requests.ConnectionError as ec:
            print('I cannot connect to ' + stUrl + ' ' + str(ec))
            sys.exit(1)
        except requests.exceptions.HTTPError as eh:
            print('HTTP Error' + str(eh))
            sys.exit(1)
        except requests.exceptions.Timeout as et:
            print('Timeout Error:' + str(et))
            sys.exit(1)
        except requests.exceptions.RequestException as e:
            print('Unknown Error' + str(e))
            sys.exit(1)
        else:
            apiCount.value += 1
            jsonResponse = response.json()
            jsonAccounts = jsonResponse["result"]

            if len(jsonAccounts) == 0:
                keepLooping = False
                continue
            for item in jsonAccounts:
                stUserAccountName = item.get("name")
                if namePattern in stUserAccountName:
                    accNumQ.put(stUserAccountName)

        entry+=numberToFetchEachTime

def stDeleteAccount(accNumQ, referer, stUrl, timeout, count, namePattern, auth):
    # This is created as a separate process - so no memory inheritance takes place

    import base64
    import queue
    import requests

    # turn off annoying messages
    from requests.packages.urllib3.exceptions import InsecureRequestWarning
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # stLogin/stLogout read stUrl, referer, stTimeout and apiCount as module
    # globals, which do not exist yet in this process - confirmed directly:
    # NameError on stUrl under macOS/Windows multiprocessing, whose default
    # "spawn" start method re-imports this module fresh in the child rather
    # than inheriting the parent's already-executed __main__ block the way a
    # forked child (Linux's default) would. Seed them from the arguments
    # this function was actually given before calling either.
    globals()['stUrl'] = stUrl
    globals()['referer'] = referer
    globals()['stTimeout'] = timeout
    globals()['apiCount'] = count

    # We'll use session management and login to ST via /myself - auth, not
    # the module global basicAuth, which is equally unset here for the same
    # reason.
    csrftoken = stLogin(auth, sessionMgt)

    headers = {'Referer': 'PippinTheCat',       # This must be the same as the /myself use case
               'csrfToken': csrftoken,
               'Accept': 'application/json'}
    while True:
        try:
            accName = accNumQ.get(block=False, timeout=timeout)
        except queue.Empty:
            # Nothing left to process
            break
        else:
            url = stUrl + 'accounts/' + accName
            try:
                response = sessionMgt.delete(url, headers=headers, verify=False, timeout=timeout)
            except requests.ConnectionError as ec:
                print('I cannot connect to ' + stUrl + ' ' + str(ec))
                sys.exit(1)
            except requests.exceptions.HTTPError as eh:
                print('HTTP Error' + str(eh))
                sys.exit(1)
            except requests.exceptions.Timeout as et:
                print('Timeout Error:' + str(et))
                sys.exit(1)
            except requests.exceptions.RequestException as e:
                print('Unknown Error' + str(e))
                sys.exit(1)
            else:
                count.value+=1
                continue
    stLogout(sessionMgt, csrftoken)
    return
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import datetime
    # import json
    import multiprocessing
    import os
    import requests
    # import ssl
    # import string
    import sys

    from multiprocessing import Process, Value, Queue
    #from requests.auth import HTTPBasicAuth
    from requests.packages.urllib3.exceptions import InsecureRequestWarning



    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment


    numberParallelProcesses = 3
    numberAccountsToCreate = 1000
    #logFile = 'updateConfig.log'  # We won't use a logFile for this example
    stTimeout = 60  # in seconds
    referer = 'PippinTheCat'
    #basicAuth = "<BASE64_ENCODED_USERNAME_COLON_PASSWORD>"  # from echo -n user:pass | base64
    namePattern = 'ZZ'  # if an ST username contains this - then delete it!

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
        sys.exit(0)

    stServer = stConfig.get('st_server', '')
    stPort = stConfig.get('st_port', '')
    stUser = stConfig.get('st_user', '')
    stPassword = stConfig.get('st_password', '')

    if not stServer or not stPort or not stUser or not stPassword:
        print('The configuration file must set st_server, st_port, st_user and st_password.')
        sys.exit(0)

    #
    # Build the values the API calls need. The base64 Authorization value is
    # derived here, so there is no need to encode it by hand.
    #
    stUrl = 'https://' + stServer + ':' + stPort + '/api/v2.0/'
    basicAuth = base64.b64encode((stUser + ':' + stPassword).encode()).decode()

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

    # Counter of how many APIs get issued
    apiCount = Value('i', 0)

    # We are turning off Cert validation - stop the warning messages
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)
    
    # Create a multiprocessing Queue which will be shared amongst our parallel procs.
    accNumQ = Queue()

    # Now populate the Queue with a list of all accounts that we wish to delete.
    # Build this list in a single threaded way

    stGetAccounts(accNumQ)

    processes = [Process(target=stDeleteAccount, args=(accNumQ, referer, stUrl, stTimeout, apiCount, namePattern, basicAuth)) for x in range(numberParallelProcesses)]
    for p in processes:
        p.start()

    for p in processes:
        p.join()

    accNumQ.close()

    stLogout(sessionMgt, csrftoken)
    print('I issued: ' + str(apiCount.value) + ' APIs')
    outputString = 'Ending at: ' + str(datetime.datetime.now())
    print(outputString)
