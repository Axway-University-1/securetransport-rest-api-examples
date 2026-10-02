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
# V1.00 Plamen Milenkov  15-Sep-2025  Migrated from the python2 examples
#                                     stUpdateSimpleRouteFields.py and
#                                     stUpdateStepFields.py, which are replaced
#                                     by this script. CSRF compliant.
#
# This script scans every SIMPLE route on the system and patches fields on the
# routes that match. It shows the two PATCH shapes you need for route
# maintenance:
#
#   1. A field on the route itself, for example the failure notification list.
#   2. A field inside one step of the route, addressed by its step index, for
#      example the host and port of a Sentinel custom step.
#
# The second is the interesting one. A step has no id of its own, so it is
# addressed by its position in the steps array. That means you have to read the
# route first to find the index of the step you want.
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /routes  GET, PATCH
#
# Usage: python3 stUpdateAllRoutes.py
#
#        Set dryRun to True in the configuration section to see what would be
#        changed without changing anything. Start there.
#
# Outputs:
#    A summary of the routes inspected and patched, on standard output.
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


# Send one PATCH to a route.
#
# jsonIn is a JSON Patch document: a list of operations, each with an op of
# add, replace or remove, and a path that is a JSON Pointer into the route.
#
def stPatchRoute(session, csrftoken, routeId, jsonIn):

    url = stUrl + 'routes/' + str(routeId)

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

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
            print('   Patch of route ' + str(routeId) + ' returned ' + str(response.status_code))
            print('   ' + str(response.text))
            return False
        print('   Patched route ' + str(routeId))
        return True


# Example 1, a field on the route itself.
#
# The failure notification field holds a comma separated list of addresses.
# This removes one address and leaves the rest alone, which is the usual job
# when somebody leaves a team.
#
def stRemoveFailureEmail(session, csrftoken, route):

    failMail = route.get('failureEmailName')
    if not failMail or emailToRemove not in failMail:
        return False

    remaining = [a.strip() for a in failMail.split(',') if a.strip() and a.strip() != emailToRemove]
    newValue = ','.join(remaining)

    print('Route ' + str(route.get('name')) + ' has failure email: ' + failMail)
    print('   it will become: ' + (newValue if newValue else '<empty>'))

    jsonIn = [{'op': 'replace',
               'path': '/failureEmailName',
               'value': newValue}]

    return stPatchRoute(session, csrftoken, route.get('id'), jsonIn)


# Example 2, fields inside one step of the route.
#
# A step is addressed by its index in the steps array, so the route has to be
# read first. Here we look for a step of a given type and repoint it at a new
# host and port. In the original use case this was a custom step that sends
# extra events to Sentinel, and Sentinel had moved.
#
def stUpdateMatchingStep(session, csrftoken, route):

    steps = route.get('steps')
    if not steps:
        return False

    patched = False

    for stepIndex, step in enumerate(steps):

        # Is this the step type you are looking for?
        if stepTypeToUpdate not in str(step.get('type')):
            continue

        properties = step.get('customProperties')
        if not properties:
            continue

        # Only touch a step that actually carries the fields we are changing
        if properties.get('mPort') is None and properties.get('mHostName') is None:
            continue

        print('Route ' + str(route.get('name')) + ' step ' + str(stepIndex) +
              ' is a ' + str(step.get('type')))
        print('   host ' + str(properties.get('mHostName')) +
              ' port ' + str(properties.get('mPort')))

        jsonIn = [{'op': 'replace',
                   'path': '/steps/' + str(stepIndex) + '/customProperties/mHostName',
                   'value': newStepHost},
                  {'op': 'replace',
                   'path': '/steps/' + str(stepIndex) + '/customProperties/mPort',
                   'value': newStepPort}]

        if stPatchRoute(session, csrftoken, route.get('id'), jsonIn):
            patched = True

    return patched


# Fetch every SIMPLE route, a page at a time, and hand each one to the
# examples above.
#
def stProcessSimpleRoutes(session, csrftoken):

    entry = 0
    numberObjectsToFetchPerCall = 200
    keepLooping = True

    numberOfRoutes = 0
    numberPatched = 0

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    while keepLooping:

        url = (stUrl + 'routes?type=SIMPLE&offset=' + str(entry) +
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
                print('GET routes returned ' + str(response.status_code))
                sys.exit(1)

            routes = response.json()

            resultSet = routes.get('resultSet', {})
            returnCount = resultSet.get('returnCount', 0)

            if returnCount < numberObjectsToFetchPerCall:
                keepLooping = False

            for route in routes.get('result', []):
                numberOfRoutes += 1

                changed = False
                if updateFailureEmail:
                    changed = stRemoveFailureEmail(session, csrftoken, route) or changed
                if updateStepFields:
                    changed = stUpdateMatchingStep(session, csrftoken, route) or changed

                if changed:
                    numberPatched += 1

            entry += numberObjectsToFetchPerCall

    return numberOfRoutes, numberPatched


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

    # Which of the two examples to run
    updateFailureEmail = True
    updateStepFields = True

    # Example 1, the route level field
    emailToRemove = 'oldteam@example.com'

    # Example 2, the step level fields
    stepTypeToUpdate = 'CustomStepTracking'
    newStepHost = 'sentinel.example.com'
    newStepPort = '1325'

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

    numRoutes, numPatched = stProcessSimpleRoutes(sessionMgt, csrftoken)

    print('')
    print('I inspected: ' + str(numRoutes) + ' simple routes')
    print('I patched:   ' + str(numPatched) + ' of them')

    stLogout(sessionMgt, csrftoken)
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
