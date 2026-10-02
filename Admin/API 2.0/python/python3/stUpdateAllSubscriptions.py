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
# V1.00 Plamen Milenkov  15-Sep-2025  Migrated from the python2 example
#                                     stUpdateSubscriptionFields.py, which is
#                                     replaced by this script. CSRF compliant.
#
# This script scans every subscription on the system and patches a set of fields
# on each one. The original use case was a migration: the ExtraRouting migration
# tool did not carry over a few subscription settings, so they had to be set
# across the estate afterwards.
#
# It also shows the difference between the two PATCH operations you will reach
# for most often:
#
#   replace - the field already exists and you want a new value
#   add     - the field is not set yet, and you want to create it
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /subscriptions  GET, PATCH
#
# Usage: python3 stUpdateAllSubscriptions.py
#
#        Set dryRun to True in the configuration section to see what would be
#        changed without changing anything. Start there.
#
# Outputs:
#    A summary of the subscriptions inspected and patched, on standard output.
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


# Send one PATCH to a subscription
#
def stPatchSubscription(session, csrftoken, subscriptionId):

    url = stUrl + 'subscriptions/' + str(subscriptionId)

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    #
    # replace expects the field to be there already. add creates it. Sending
    # replace for a field that is not set, or add for one that is, is the usual
    # cause of a 422 back from this endpoint.
    #
    jsonIn = [{'op': 'replace',
               'path': '/postProcessingActions/ppaOnSuccessInDoDelete',
               'value': True},
              {'op': 'add',
               'path': '/subscriptionEncryptMode',
               'value': 'Default'},
              {'op': 'add',
               'path': '/flowAttrsMergeMode',
               'value': 'preserve'},
              {'op': 'add',
               'path': '/maxParallelSitPulls',
               'value': '10'}]

    if dryRun:
        print('   DRY RUN, would send: ' + json.dumps(jsonIn))
        return True

    try:
        response = session.patch(url, headers=headers, json=jsonIn, verify=False, timeout=stTimeout)
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
        if response.status_code != 204:
            print('   Patch of subscription ' + str(subscriptionId) +
                  ' returned ' + str(response.status_code))
            print('   ' + str(response.text))
            return False
        print('   Patched subscription ' + str(subscriptionId))
        return True


# Fetch every subscription, a page at a time, and patch each one
#
def stProcessSubscriptions(session, csrftoken):

    entry = 0
    numberObjectsToFetchPerCall = 200
    keepLooping = True

    numberOfSubscriptions = 0
    numberPatched = 0

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    while keepLooping:

        url = (stUrl + 'subscriptions?offset=' + str(entry) +
               '&limit=' + str(numberObjectsToFetchPerCall))

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
                print('GET subscriptions returned ' + str(response.status_code))
                sys.exit(1)

            subscriptions = response.json()

            resultSet = subscriptions.get('resultSet', {})
            returnCount = resultSet.get('returnCount', 0)

            if returnCount < numberObjectsToFetchPerCall:
                keepLooping = False

            for item in subscriptions.get('result', []):
                numberOfSubscriptions += 1

                subscriptionId = item.get('id')

                # Restrict the run to one subscription type, if asked to
                if subscriptionTypeToUpdate:
                    if subscriptionTypeToUpdate not in str(item.get('type')):
                        continue

                print('Subscription ' + str(subscriptionId) +
                      ' account ' + str(item.get('account')) +
                      ' type ' + str(item.get('type')))

                if stPatchSubscription(session, csrftoken, subscriptionId):
                    numberPatched += 1

            entry += numberObjectsToFetchPerCall

    return numberOfSubscriptions, numberPatched


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import json
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

    # Report what would change, without changing anything. Run with this set to
    # True first, and read the output, before you let it write.
    dryRun = True

    # Leave empty to process every subscription, or set a type such as
    # 'SharedFolder' to restrict the run.
    subscriptionTypeToUpdate = ''

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

    if dryRun:
        print('Running in DRY RUN mode, nothing will be changed.')
        print('')

    # We are turning off Cert validation - stop the warning messages
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    numSubs, numPatched = stProcessSubscriptions(sessionMgt, csrftoken)

    print('')
    print('I inspected: ' + str(numSubs) + ' subscriptions')
    print('I patched:   ' + str(numPatched) + ' of them')

    stLogout(sessionMgt, csrftoken)
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
