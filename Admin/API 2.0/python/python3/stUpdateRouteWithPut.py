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
#                                     stUpdateSimpleRouteAddSteps.py,
#                                     stLinkSimpleToComposite.py and
#                                     stAddCompositeRouteToSubscription.py,
#                                     which are replaced by this script.
#                                     CSRF compliant.
#
# Some changes to a route cannot be expressed as a PATCH. Inserting a step into
# the middle of an existing steps array is the clearest case: with the V2 API the
# only reliable way is to read the whole route, change the copy, and PUT it back.
#
# That read, change, write cycle is the single most useful technique in this
# folder, and it is the same for three jobs that look different:
#
#   1. Insert one or more new steps into an existing route, at a chosen position.
#   2. Link an existing simple route into a composite route, by giving the
#      composite an ExecuteRoute step that points at the simple route.
#   3. Attach a composite route to a subscription.
#
# All three are a GET of /routes/{id}, an edit of the returned object, and a PUT
# of the result back to the same URL. Pick which one to run in the configuration
# section.
#
# Take care with PUT: it replaces the whole object. Always send back the object
# you read, with your change applied, and never a hand built fragment.
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /routes  GET, PUT
#
# Usage: python3 stUpdateRouteWithPut.py <routeId> [secondId]
#
#        routeId  - the route to change.
#        secondId - for mode 'link', the id of the simple route to execute.
#                   For mode 'subscription', the id of the subscription.
#                   Not needed for mode 'insert'.
#
#        Set dryRun to True in the configuration section to see the object that
#        would be sent without sending it. Start there.
#
# Outputs:
#    A description of the change, on standard output.
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


# Read one route and return it as a python dictionary
#
def stGetRoute(session, csrftoken, routeId):

    url = stUrl + 'routes/' + str(routeId)

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
            print('Cannot read route ' + str(routeId) + ', HTTP ' + str(response.status_code))
            sys.exit(1)
        return response.json()


# Write the whole route back.
#
# PUT replaces the object, so what we send is the object we read with the edit
# applied to it.
#
def stPutRoute(session, csrftoken, routeId, route):

    url = stUrl + 'routes/' + str(routeId)

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    if dryRun:
        print('DRY RUN, would PUT this object back to ' + url + ':')
        print(json.dumps(route, indent=2))
        return True

    try:
        response = session.put(url, headers=headers, json=route, verify=False, timeout=stTimeout)
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
            print('PUT of route ' + str(routeId) + ' returned ' + str(response.status_code))
            print(str(response.text))
            return False
        print('Successfully updated route ' + str(routeId))
        return True


# Mode 'insert'
#
# Insert the steps in stepsToInsert into the route's steps array, at
# insertAtOffset. An offset of 0 puts them first, and an offset equal to the
# number of existing steps puts them last.
#
def stInsertSteps(route):

    steps = route.get('steps')
    if steps is None:
        steps = []
        route['steps'] = steps

    offset = insertAtOffset
    if offset < 0 or offset > len(steps):
        print('The insert offset ' + str(offset) + ' is outside this route, which has ' +
              str(len(steps)) + ' steps.')
        return False

    print('Route ' + str(route.get('name')) + ' has ' + str(len(steps)) + ' steps')
    print('Inserting ' + str(len(stepsToInsert)) + ' step(s) at offset ' + str(offset))

    route['steps'] = steps[:offset] + stepsToInsert + steps[offset:]
    return True


# Mode 'link'
#
# Give a composite route an ExecuteRoute step that points at an existing simple
# route. This is what the admin UI does when you extend a package route.
#
def stLinkSimpleRoute(route, simpleRouteId):

    print('Composite route ' + str(route.get('name')) +
          ' will be given an ExecuteRoute step for simple route ' + str(simpleRouteId))

    route['steps'] = [{'type': 'ExecuteRoute',
                       'status': 'ENABLED',
                       'autostart': False,
                       'executeRoute': simpleRouteId}]
    return True


# Mode 'subscription'
#
# Attach the route to a subscription. The route carries the list of
# subscriptions it belongs to.
#
def stAttachToSubscription(route, subscriptionId):

    existing = route.get('subscriptions')
    if existing is None:
        existing = []

    if subscriptionId in existing:
        print('Route ' + str(route.get('name')) +
              ' is already attached to subscription ' + str(subscriptionId))
        return False

    print('Route ' + str(route.get('name')) +
          ' will be attached to subscription ' + str(subscriptionId))

    # Keep any subscriptions the route already belongs to
    route['subscriptions'] = existing + [subscriptionId]
    return True


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
    referer = 'PippinTheCat'

    # Show the object that would be sent, without sending it. Run with this set
    # to True first, and read the output, before you let it write.
    dryRun = True

    # Which of the three jobs to do: 'insert', 'link' or 'subscription'
    mode = 'insert'

    # For mode 'insert', where to put the new steps and what they are.
    # An offset of 0 makes them the first steps of the route.
    insertAtOffset = 0

    stepsToInsert = [{'type': 'EncodingConversion',
                      'status': 'ENABLED',
                      'conditionType': 'ALWAYS',
                      'usePrecedingStepFiles': False,
                      'fileFilterExpression': '*',
                      'fileFilterExpressionType': 'GLOB',
                      'inputCharset': 'UTF-8',
                      'outputCharset': 'UTF-8',
                      'actionOnStepFailure': 'PROCEED'}]

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

    if mode not in ('insert', 'link', 'subscription'):
        print("mode must be one of 'insert', 'link' or 'subscription'")
        sys.exit(0)

    try:
        routeId = sys.argv[1]
    except IndexError:
        print('Please provide argument 1, the id of the route to change.')
        print('Usage: python3 stUpdateRouteWithPut.py <routeId> [secondId]')
        sys.exit(0)

    secondId = None
    if mode in ('link', 'subscription'):
        try:
            secondId = sys.argv[2]
        except IndexError:
            if mode == 'link':
                print('Please provide argument 2, the id of the simple route to execute.')
            else:
                print('Please provide argument 2, the id of the subscription.')
            sys.exit(0)

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

    # 1. Read the route
    theRoute = stGetRoute(sessionMgt, csrftoken, routeId)

    # 2. Change our copy of it
    if mode == 'insert':
        changed = stInsertSteps(theRoute)
    elif mode == 'link':
        changed = stLinkSimpleRoute(theRoute, secondId)
    else:
        changed = stAttachToSubscription(theRoute, secondId)

    # 3. Write the whole thing back
    if changed:
        stPutRoute(sessionMgt, csrftoken, routeId, theRoute)
    else:
        print('Nothing to change.')

    stLogout(sessionMgt, csrftoken)
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
