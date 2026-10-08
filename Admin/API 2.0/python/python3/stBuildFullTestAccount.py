#! /usr/bin/python3
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
# V3.00 Plamen Milenkov  08-Oct-2026 The status of every call is checked, and a call that fails ends the
#                                    script with exit code 1 (it used to carry on, and a create that
#                                    was refused was reported as done). The id of a new object is read
#                                    from the Location header and a missing one is an error, not a
#                                    KeyError. A missing config, key file or argument exits non-zero.
# V2.00 Ian Percival   21-Jun-2023   Fix errors + csrf compliant
#                                    This code assumes that Webservices.Admin.CsrfToken.enabled is set to 'true' which is the default
#                                    for ST after and including the 20230525 release.
# V1.00 Ian Percival   23-Nov-2021
#
# This script will Build a Single Test account on SecureTransport
#
# It is single threaded - issuing APIs in a similar way you would onboard a user process, so is useful to demonstrate
#   onboarding principles.
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /accounts  POST
#             /certificates GET, POST
#             /sites POST
#             /routes GET, POST
#             /subscriptions POST
#
# Usage: python3 stBuildFullTestAccount.py
#
# Risk: write - creates an account with a key, two transfer sites, a subscription and two routes, under fixed names
#
# Notes:
# - The names are fixed (the account TestAccount1, the sites FolderMonitor and SFTPsite, the routes
#   SimpleRouteToSFTPsite and PackageRouteToSFTPsite). If one is there already the server refuses it and
#   the script exits 1, leaving what it made before that: remove it by hand.
# - It needs a private key file named testsshkey in the folder it is run from, and the route template
#   named in templateRouteName (Empty) to be there.
# - The caPassword of the key import is the one of the server's own certificate authority: "change_me" is
#   a placeholder, and the server refuses it with "Specify a valid CA Password.".
# - Exit codes: 0 done, 1 anything failed.
#
# Outputs:
#    The ids of what it made, on standard output.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#

import base64
import datetime
import json
import multiprocessing
import os
import re              # Regular Expressions
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning

# All functions are defined below


# Send one request. Anything that keeps the call from completing is fatal: the script
# says what failed and exits 1. An HTTP status is not an exception, so the caller
# looks at it (see stExpect).
def stCall(method, url, **kwargs):
    try:
        response = getattr(sessionMgt, method.lower())(url, verify=stVerify, timeout=stTimeout, **kwargs)
    except requests.exceptions.Timeout as et:
        print('Timeout talking to ' + url + ': ' + str(et))
        sys.exit(1)
    except requests.exceptions.ConnectionError as ec:
        print('I cannot connect to ' + url + ': ' + str(ec))
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        print('The request to ' + url + ' failed: ' + str(e))
        sys.exit(1)
    apiCount.value += 1
    return response


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        print(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) + ': ' + str(response.text)[:300])
        sys.exit(1)


# The id of a new object: the last part of its Location header, which looks like
#   https://<SERVER>:8444/api/v2.0/sites/8a0101967d2e236c017d766239902d02
def stIdFromLocation(response, what):
    location = response.headers.get('location')
    if not location:
        print(what + ' answered ' + str(response.status_code) + ' with no Location header')
        sys.exit(1)
    # all after the last occurrence of /
    # match at least one of anything not a slash folowed by end of string
    return re.search('[^/]+$', location).group(0)


# This is the ST logout session management
#
# This is the ST /myself DELETE method

def stLogout(session, csrftoken):

    url = stUrl + 'myself'

    headers =  {'Referer': referer,
                'csrfToken': csrftoken,
                'Accept': 'application/json'}

    response = stCall('DELETE', url, headers=headers)
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

    response = stCall('POST', url, headers=headers)
    stExpect(response, 200, 'Login')

    # Successful login

    # {
    #     "message" : "Logged in"
    # }
    if response.json().get('message') != 'Logged in':
        print('The login did not answer "Logged in"')
        sys.exit(1)
    print('Session Login')
    return response.headers.get('csrfToken')


def stCreateAccount(token):

    url = stUrl + 'accounts'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type' :'application/json',
               'Accept': 'application/json'}



    # Minimum JSON required to create an account.  Add other fields as required
    jsonIn = { "type" : "user",
                "uid": "1000",
                "gid": "1000",
                "name": accName,
                "homeFolder": homeFolder,
                "user": { "name": accName,
                          "passwordCredentials": {"password": "change_me"}
                        }
              }

    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the account')
    return True

# This will import a private key stored as a file
# It demonstrates using multipart/mixed format payloads which are used by ST
#
def stImportKey(token):
    url = stUrl + 'certificates'
    boundary = 'FlokiKat'
    contT = 'multipart/mixed; boundary=' + boundary

    headers = {'Referer': referer,
               'Content-Type': contT,
               'csrfToken': token,
               'Accept': 'application/json'}

    jsonIn = {"name": "PrivateSSHKey",
            "subject": "C=US,CN=sshKey",
            "caPassword": "change_me",
            "account" : accName,
            "type" : "ssh",
            "password": "change_me",
            "usage": "private",
            "keySize": "2048",
            "validityPeriod": "720"
           }


    # We need to build our multipart content as a byte stream to transmit to ST
    # Now generate the JSON part of our multipart
    jsonsection = '--' + boundary + '\n'
    jsonsection += 'Content-Type: application/json\n\n'
    jsonsection += json.dumps(jsonIn)
    jsonsection += '\n\n'

    certBeginSection = '--' + boundary + '\n'
    certBeginSection += 'Content-Type: application/octet-stream\n\n'
    certEndSection = '\n--' + boundary + '--\n'
    certEndSection = certEndSection.encode()

    multipart = jsonsection + certBeginSection
    multipart = multipart.encode()

    try:
        with open('testsshkey', mode='rb') as file:
            binaryCert = file.read()
    except IOError:
        print('I cannot read the private key file testsshkey in ' + os.getcwd())
        sys.exit(1)

    multipartBytes = multipart + binaryCert + certEndSection

    response = stCall('POST', url, data=multipartBytes, headers=headers)
    stExpect(response, 200, 'Certificate Import')
    return True
    # Python / ST bug - location header not visible! We should be able to simply do

    #a = re.search('[^/]+$',response.headers['location'])
    #certId = a.group(0)
    #return certId

def stGetKeyId(token):

    # As location header is missing - do another GET to find the id
    url = stUrl + 'certificates?usage=private&account=' + accName + '&name=PrivateSSHKey'
    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall('GET', url, headers=headers)
    stExpect(response, 200, 'Certificate Find')
    rJson = response.json()

    resultSet = rJson['resultSet']
    returnCount = resultSet['returnCount']
    if returnCount != 1:
        print('I cannot find the Certificate')
        sys.exit(1)

    # should only be the 1 result as the name is unique
    results = rJson['result']
    certId = results[0]['id']
    print(certId)
    return certId


def stCreateSiteFolder(token):

    url = stUrl + 'sites'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    # Minimum JSON required to create a folder monitor.  Add other fields as required
    jsonIn = {"type": "folder",
              "name": "FolderMonitor",
              "account" : accName,
              "protocol": "folder",
              "downloadFolder": "/tmp",
              "downloadPattern": "nofiles",
              "uploadFolder": "/tmp"
              }

    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the folder monitor site')

    # No JSON is returned by the create.
    #
    # To find the id of the newly created object:
    # Search the returned location header for all after the last occurrence of /
    # location header looks like this:
    # https://<SERVER>:8444/api/v2.0/sites/8a0101967d2e236c017d766239902d02
    folderId = stIdFromLocation(response, 'Creating the folder monitor site')
    return True

def stCreateSiteSFTP(keyId,token):

    url = stUrl + 'sites'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    # Minimum JSON required to create an SFTP site.  Add other fields as required
    jsonIn = {"type": "ssh",
              "name": "SFTPsite",
              "account" : accName,
              "protocol": "ssh",
              "downloadFolder": "/tmp",
              "downloadPattern": "nofiles",
              "uploadFolder": "/tmp",
              "host": "<SERVER>",
              "port": "22",
              "userName": "stapp",
              "password": "change_me",
              "usePassword": True
              }
    # Use this to add Key based access
    jsonIn = {"type": "ssh",
              "name": "SFTPsite",
              "account" : accName,
              "protocol": "ssh",
              "downloadFolder": "/tmp",
              "downloadPattern": "nofiles",
              "uploadFolder": "/tmp",
              "host": "<SERVER>",
              "port": "22",
              "userName": "stapp",
              "usePassword": False,
              "clientCertificate": keyId
              }


    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the SFTP site')

    # No JSON is returned by the create. The id of the new site is in the Location header
    sftpSiteId = stIdFromLocation(response, 'Creating the SFTP site')
    return True

def stCreateSubscription(token):
    url = stUrl + 'subscriptions'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    jsonIn = {
              "type": "AdvancedRouting",
              "application": "AdvRouting",
              "folder": "/inbound",
              "account": accName,
              "transferConfigurations": [{
                                           "tag": "PARTNER-IN",
                                           "outbound": False
                                         }
                                         ],
              "postProcessingActions": {
                                           "ppaOnSuccessInDoDelete": True
                                       }
              }
    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the subscription')

    # No JSON is returned by the create. The id of the new subscription is in the Location header
    subId = stIdFromLocation(response, 'Creating the subscription')
    print(subId)
    return subId


def stCreateSimpleRoute(token):
    url = stUrl + 'routes'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    # Minimum JSON required to create a Simple Route with a Send to Partner Step.  Add other fields as required
    jsonIn = {"type": "SIMPLE",
              "name": "SimpleRouteToSFTPsite",
              "conditionType": "ALWAYS",
              "condition": True,
              "steps" : [ {
                            "type": "SendToPartner",
                            "status": "ENABLED",
                            "autostart" : False,
                            "transferSiteExpressionType": "LIST",
                            "transferSiteExpression": "SFTPsite#!#CVD#!#",
                            "fileFilterExpressionType": "GLOB",
                            "fileFilterExpression": "*",
                            "actionOnStepFailure": "FAIL"
              }]
              }

    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the simple route')

    sRouteId = stIdFromLocation(response, 'Creating the simple route')
    print('Simple Route Id: ' + sRouteId)
    return sRouteId

def stCreatePackageRoute(sRouteId,subId, tRouteId, token):
    url = stUrl + 'routes'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    # Minimum JSON required to create a Package Route.  Add other fields as required
    # Note the use of he executeRoute step to link the Simple Route to the Composite/Package
    jsonIn = {"type": "COMPOSITE",
              "account" : accName,
              "name": "PackageRouteToSFTPsite",
              "conditionType": "MATCH_ALL",
              "routeTemplate" : tRouteId,
              "subscriptions": [ subId ],
              "steps" : [{
                            "type": "ExecuteRoute",
                            "status": "ENABLED",
                            "autostart": False,
                            "executeRoute": sRouteId
    }]}

    response = stCall('POST', url, json=jsonIn, headers=headers)
    stExpect(response, 201, 'Creating the package route')

    pRouteId = stIdFromLocation(response, 'Creating the package route')
    print('Package Route Id: ' + pRouteId)
    return pRouteId

def stGetTemplateRouteId(name, token):

    url = stUrl + 'routes?type=TEMPLATE&name=' + str(name)

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall('GET', url, headers=headers)
    stExpect(response, 200, 'Looking for the route template ' + str(name))
    rJson = response.json()

    resultSet = rJson['resultSet']
    returnCount = resultSet['returnCount']
    if returnCount != 1:
        print('I cannot find the Route Package Template')
        sys.exit(1)

    # should only be the 1 result as the name is unique
    results = rJson['result']
    templateId = results[0]['id']
    print(templateId)
    return templateId




# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    #logFile = 'updateConfig.log'   # We won't use a logFile for this example
    stTimeout = 60                  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'        # Used for Session Managtement - cab be anything so long as always the same
    #basicAuth = "<BASE64_ENCODED_USERNAME_COLON_PASSWORD>"  # from echo -n user:pass | base64

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


    # Parameters used to create an account
    accName = 'TestAccount1'
    homeFolder = '/usrdata/NoBU/' + accName
    templateRouteName = 'Empty'
    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    # Tell the user about our run time environment for multiprocessing
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
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session which will be shared amongst all APIs
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    # Create the base user account
    stCreateAccount(csrftoken)

    # Import an SSH private Key
    stImportKey(csrftoken)

    # Find the ID of the created SSH private key
    sshKeyId = stGetKeyId(csrftoken)

    # Create a Folder Monitor Transfer Site
    stCreateSiteFolder(csrftoken)

    # Create an SFTP transfer Site
    stCreateSiteSFTP(sshKeyId,csrftoken)

    # Create a Subscription
    subId = stCreateSubscription(csrftoken)

    # Create a Simple Route
    sRouteId = stCreateSimpleRoute(csrftoken)

    # Get Template Route ID
    tRouteId = stGetTemplateRouteId(templateRouteName, csrftoken)

    # Create a Package Route
    pRouteId = stCreatePackageRoute(sRouteId,subId, tRouteId, csrftoken)

    stLogout(sessionMgt, csrftoken)
    print('I issued: ' + str(apiCount.value) + ' APIs')
    outputString = 'Ending at: ' + str(datetime.datetime.now())
    print(outputString)
