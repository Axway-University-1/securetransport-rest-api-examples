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
# V1.00 Plamen Milenkov  15-Sep-2025  Migrated from the python2 example of the
#                                     same name, which is replaced by this
#                                     script. CSRF compliant.
#
# This script answers a question the admin UI does not answer directly: which
# accounts have access to each shared folder?
#
# The answer needs two collections joined:
#
#   /applications  - a SharedFolder application knows the real folder on disk
#   /subscriptions - a SharedFolder subscription links an account to one of
#                    those applications, and knows the folder name the user
#                    sees when they log in
#
# So we read the applications first to build a map of application name to the
# folder on disk, then read the subscriptions and group the accounts by the
# application they subscribe to.
#
# This script only reads. It changes nothing.
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /applications   GET
#             /subscriptions  GET
#
# Usage: python3 stUsersPerSharedFolder.py
#
# Outputs:
#    One block per shared folder, listing the accounts that subscribe to it,
#    on standard output.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

# All functions are defined below


# This is the ST logout session management
#
# This is the ST /myself DELETE method
#
def stLogout(session, token):

    url = stUrl + 'myself'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}
    try:
        response = session.delete(url, headers=headers, verify=False, timeout=stTimeout)
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
        print('Unknown Error: ' + str(e))
        sys.exit(1)
    else:
        print('Session Mgt Logged Out')
        numAPIs.value += 1
        return True


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
        numAPIs.value += 1
        if response.status_code != 200:
            print('Cannot login ', response.status_code)
            sys.exit(1)
        jsonResponse = response.json()
        csrftoken = response.headers.get('csrfToken')
        message = jsonResponse.get('message')
        if 'Logged in' == message:
            print('Session Login')
            return csrftoken
        else:
            print('Login Failure ', response.status_code)
            sys.exit(1)


# Read one page of a collection and return the parsed body
#
def stGetPage(session, csrftoken, collection, offset, limit):

    url = (stUrl + collection + '?offset=' + str(offset) + '&limit=' + str(limit))

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    try:
        response = session.get(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        print('I cannot connect to ' + url + ' ' + str(ec))
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
        numAPIs.value += 1
        if response.status_code != 200:
            print('GET ' + collection + ' returned ' + str(response.status_code))
            sys.exit(1)
        return response.json()


# Build a map of SharedFolder application name to the folder it points at
# on disk.
#
def stReadApplications(session, csrftoken):

    sharedFolderApps = {}

    entry = 0
    numberObjectsToFetchPerCall = 200
    keepLooping = True

    while keepLooping:

        page = stGetPage(session, csrftoken, 'applications', entry, numberObjectsToFetchPerCall)

        returnCount = page.get('resultSet', {}).get('returnCount', 0)
        if returnCount < numberObjectsToFetchPerCall:
            keepLooping = False

        for item in page.get('result', []):
            if 'SharedFolder' not in str(item.get('type')):
                continue
            sharedFolderApps[item.get('name')] = item.get('sharedFolder')

        entry += numberObjectsToFetchPerCall

    return sharedFolderApps


# Group the accounts by the SharedFolder application they subscribe to.
#
# The folder recorded on the subscription is the name the user sees when they
# log in, for example through the web client. The real folder on disk is the one
# defined on the application, which is why both collections are needed.
#
def stProcessSubscriptions(session, csrftoken):

    sharedFolderAccounts = {}
    userVisibleFolders = {}

    entry = 0
    numberObjectsToFetchPerCall = 200
    keepLooping = True

    while keepLooping:

        page = stGetPage(session, csrftoken, 'subscriptions', entry, numberObjectsToFetchPerCall)

        returnCount = page.get('resultSet', {}).get('returnCount', 0)
        if returnCount < numberObjectsToFetchPerCall:
            keepLooping = False

        for item in page.get('result', []):

            # ignore any non SharedFolder subscriptions
            if 'SharedFolder' not in str(item.get('type')):
                continue

            application = item.get('application')
            account = item.get('account')

            sharedFolderAccounts.setdefault(application, []).append(account)
            userVisibleFolders.setdefault(application, set()).add(item.get('folder'))

        entry += numberObjectsToFetchPerCall

    return sharedFolderAccounts, userVisibleFolders


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import os
    import requests
    import sys

    from multiprocessing import Value
    from requests.packages.urllib3.exceptions import InsecureRequestWarning

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'

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

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    # We are turning off Cert validation - stop the warning messages
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    sharedFolderApps = stReadApplications(sessionMgt, csrftoken)
    print('Found ' + str(len(sharedFolderApps)) + ' SharedFolder applications')

    sharedFolderAccounts, userVisibleFolders = stProcessSubscriptions(sessionMgt, csrftoken)

    print('')
    print('=' * 70)
    for application in sorted(sharedFolderApps):

        onDisk = sharedFolderApps.get(application)
        accounts = sorted(sharedFolderAccounts.get(application, []))
        seenAs = sorted(f for f in userVisibleFolders.get(application, set()) if f)

        print('Application  : ' + str(application))
        print('Folder       : ' + str(onDisk))
        if seenAs:
            print('Users see it : ' + ', '.join(str(f) for f in seenAs))
        print('Accounts (' + str(len(accounts)) + ') : ' +
              (', '.join(str(a) for a in accounts) if accounts else 'none'))
        print('=' * 70)

    # An application with no subscriptions is worth knowing about, and so is a
    # subscription that points at something we did not see in the applications.
    orphans = [a for a in sharedFolderAccounts if a not in sharedFolderApps]
    if orphans:
        print('')
        print('These subscriptions name an application that is not a SharedFolder')
        print('application, or that no longer exists:')
        for a in sorted(orphans):
            print('   ' + str(a) + ' (' + str(len(sharedFolderAccounts[a])) + ' accounts)')

    stLogout(sessionMgt, csrftoken)
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
