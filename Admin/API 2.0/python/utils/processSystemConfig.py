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
# V2.00 Plamen Milenkov  15-Sep-2025  Converted from python2 to python3 and to
#                                     the requests library. The login and the
#                                     user class creation were commented out in
#                                     the python2 version; they now work and are
#                                     controlled by the createOnTarget setting.
#                                     CSRF compliant.
# V1.00 Ian Percival     27-Feb-2021
#
# Extract the user classes from an exported systemConfiguration.xml and convert
# them from the 5.2.1 format to the 5.5 format.
#
# The conversion that matters is the membership expression. In 5.2.1 a group
# membership test was written directly:
#
#    memberof("CN=EXAMPLE_ADMINS,OU=Groups,DC=example,DC=com",LDAP_DIR_memberOf$collection)
#
# In 5.5 the attribute has to be tested first, or the expression fails for any
# user who has no LDAP_DIR_memberOf attribute at all:
#
#    isset("LDAP_DIR_memberOf") ? memberof("CN=...",LDAP_DIR_memberOf$collection) : false
#
# The script writes the converted user classes to an XML file, and can also
# create them directly on a target server through the API.
#
# Export the system configuration via the GUI. By default it places a zip file
# in /var/tmp. Extract just the config xml with:
#
#    unzip -j export_configuration.zip systemConfiguration.xml -d /home/axway/api
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /userClasses  POST                 (only when createOnTarget is True)
#
# Usage: python3 processSystemConfig.py systemConfiguration.xml
#
# Risk: write - converts a file on this machine, and with createOnTarget set True it creates the user classes on the server
#
# Exit codes: 0 done (nothing sent, or every user class created), 1 anything failed (a user
# class the server refused included), 2 the file name is missing.
#
#        createOnTarget is False by default, so the first run only writes the
#        converted XML and tells you what it would create. Read that output
#        before turning it on.
#
# Outputs:
#    The converted user classes, as XML, in the file named by xmlFile.
#    A log file records the run.
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#
# All functions are defined first below this header.


# ---------------------
# Supporting Functions
# ---------------------

# Use a common logFile in case running in batch etc
def writeLog(logString, severity):
    # This is the logfile for our python script
    global logFile

    print(logString)

    tstamp = datetime.datetime.now()
    if severity == 'SUCCESS':
        inString = str(tstamp) + ' ' + severity + '     ' + logString + '\n'
    elif severity == 'WARNING':
        inString = str(tstamp) + ' ' + severity + '     ' + logString + '\n'
    else:
        inString = str(tstamp) + ' ' + severity + ' ' + logString + '\n'
    try:
        with open(logFile, 'a+') as fHandle:
            fHandle.write(inString)
    except IOError:
        print('Problem writing to log')
    return


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
        response = session.delete(url, headers=headers, verify=stVerify, timeout=stTimeout)
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
        if response.status_code != 200:
            print('Logout answered ' + str(response.status_code))
            sys.exit(1)
        writeLog('Session Mgt Logged Out', 'INFORMATION')
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
        response = session.post(url, headers=headers, verify=stVerify, timeout=stTimeout)
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
        if response.status_code != 200:
            print('Cannot login ', response.status_code)
            sys.exit(1)
        jsonResponse = response.json()
        csrftoken = response.headers.get('csrfToken')
        if 'Logged in' == jsonResponse.get('message'):
            writeLog('Session Login', 'INFORMATION')
            return csrftoken
        else:
            print('Login Failure ', response.status_code)
            sys.exit(1)


# Create one user class on the target server
#
# This is the ST /userClasses POST method
#
def stCreateUserClass(session, csrftoken, uclassJson):

    url = stUrl + 'userClasses'

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Content-Type': 'application/json',
               'Accept': 'application/json'}

    try:
        response = session.post(url, headers=headers, json=uclassJson,
                                verify=stVerify, timeout=stTimeout)
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
        apiCounter.value += 1
        if response.status_code != 201:
            writeLog('Could not create user class ' + str(uclassJson.get('className')) +
                     ', HTTP ' + str(response.status_code) + ' ' + str(response.text), 'FAIL')
            return False
        writeLog('Created userClass ' + str(uclassJson.get('className')), 'SUCCESS')
        return True


# Convert a 5.2.1 membership expression to the 5.5 form
#
def convertExpression(expression):

    if expression is None:
        return None
    if 'memberof' in expression:
        return 'isset("LDAP_DIR_memberOf") ? ' + expression + ' : false'
    return expression


# Read the user classes out of the exported XML and return them as a list of
# dictionaries, ready to be written out or sent to the API.
#
def extractUserClasses(inputFile):

    try:
        xmlTree = ET.parse(inputFile)
    except IOError:
        print('I cannot read the file: ' + str(inputFile))
        sys.exit(1)
    except ET.ParseError as e:
        print('The file ' + str(inputFile) + ' is not valid XML: ' + str(e))
        sys.exit(1)

    root = xmlTree.getroot()

    userClasses = []

    #
    # A UserClass in the 5.2.1 export looks like this:
    #
    # <UserClass>
    #    <name>EXAMPLE_ADMINS</name>
    #    <type>*</type>
    #    <order>1</order>
    #    <enabled>true</enabled>
    #    <user>*</user>
    #    <group>*</group>
    #    <host>*</host>
    #    <expression>memberof("CN=...",LDAP_DIR_memberOf$collection)</expression>
    #    <configurationProfile>Default</configurationProfile>
    # </UserClass>
    #
    for uclass in root.findall('./UserClass'):

        def textOf(tag):
            element = uclass.find(tag)
            return element.text if element is not None else None

        name = textOf('name')
        if name is None:
            writeLog('Skipping a UserClass with no name', 'WARNING')
            continue

        userClasses.append({'className': name,
                            'userType': textOf('type'),
                            'order': textOf('order'),
                            'group': textOf('group'),
                            'userName': textOf('user'),
                            'address': textOf('host'),
                            'enabled': textOf('enabled'),
                            'expression': convertExpression(textOf('expression'))})

    return userClasses


# Write the converted user classes out as XML
#
def writeUserClassXML(userClasses, outputFile):

    #
    # The file is opened once and truncated. The python2 version opened it in
    # append mode inside the loop, so a second run added to the first run's
    # output instead of replacing it.
    #
    try:
        with open(outputFile, 'w') as xmlHandle:
            for uc in userClasses:
                xmlHandle.write('<UserClass>\n')
                xmlHandle.write('<name>' + str(uc['className']) + '</name>\n')
                xmlHandle.write('<type>' + str(uc['userType']) + '</type>\n')
                xmlHandle.write('<order>' + str(uc['order']) + '</order>\n')
                xmlHandle.write('<enabled>' + str(uc['enabled']) + '</enabled>\n')
                xmlHandle.write('<user>' + str(uc['userName']) + '</user>\n')
                xmlHandle.write('<group>' + str(uc['group']) + '</group>\n')
                xmlHandle.write('<host>' + str(uc['address']) + '</host>\n')
                # An expression is optional, so it may legitimately be absent
                if uc['expression'] is not None:
                    xmlHandle.write('<expression>' + str(uc['expression']) + '</expression>\n')
                xmlHandle.write('</UserClass>\n')
    except IOError as e:
        print('I cannot write to ' + str(outputFile) + ': ' + str(e))
        sys.exit(1)


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import datetime
    import os
    import sys
    import xml.etree.ElementTree as ET

    from multiprocessing import Value

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'

    # Where this script keeps its output, next to the script itself
    scriptDir = os.path.dirname(os.path.abspath(__file__))
    logFile = os.path.join(scriptDir, 'extractUserClasses.log')
    xmlFile = os.path.join(scriptDir, 'convertedUserClasses.xml')

    # Set this to True to create the user classes on the target server.
    # Leave it False to convert the XML only, which is the safe first run.
    createOnTarget = False

    # A user class name longer than this is reported. The original tool carried
    # a note that the API accepts 0 to 32 characters, so anything longer is
    # worth looking at before you try to create it.
    maxClassNameLength = 32

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    # READ in the command line arguments
    try:
        inputFile = sys.argv[1]
    except IndexError:
        print('Please provide an input XML filename for me to process')
        print('Usage: python3 processSystemConfig.py systemConfiguration.xml')
        sys.exit(2)

    apiCounter = Value('i', 0)

    writeLog('Starting at ' + str(datetime.datetime.now()), 'INFORMATION')

    # ---------------------------------
    # Load and convert the input file
    # ---------------------------------
    userClasses = extractUserClasses(inputFile)
    writeLog('Total Number of UserClasses: ' + str(len(userClasses)), 'INFORMATION')

    tooLong = [uc['className'] for uc in userClasses
               if len(str(uc['className'])) > maxClassNameLength]
    if tooLong:
        writeLog('UserClasses with a name longer than ' + str(maxClassNameLength) +
                 ' characters: ' + str(len(tooLong)), 'WARNING')
        for name in tooLong:
            writeLog('   ' + str(name), 'WARNING')

    converted = [uc for uc in userClasses
                 if uc['expression'] and uc['expression'].startswith('isset(')]
    writeLog('UserClasses whose expression was converted to the 5.5 form: ' +
             str(len(converted)), 'INFORMATION')

    writeUserClassXML(userClasses, xmlFile)
    writeLog('Wrote the converted user classes to ' + str(xmlFile), 'INFORMATION')

    # ---------------------------------
    # Optionally create them on a target server
    # ---------------------------------
    if not createOnTarget:
        print('')
        writeLog('createOnTarget is False, so nothing was sent to a server.', 'INFORMATION')
        writeLog('Set it to True in the configuration section to create these ' +
                 str(len(userClasses)) + ' user classes.', 'INFORMATION')
        writeLog('Stopping at ' + str(datetime.datetime.now()), 'INFORMATION')
        sys.exit(0)

    import requests
    from requests.packages.urllib3.exceptions import InsecureRequestWarning

    #
    # Read the configuration file. It is resolved relative to this script, so
    # the script can be run from any working directory.
    #
    stConfig = {}
    configFile = os.path.join(scriptDir, '..', 'config')
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

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    sessionMgt = requests.Session()
    csrftoken = stLogin(basicAuth, sessionMgt)

    created = 0
    for uc in userClasses:
        if stCreateUserClass(sessionMgt, csrftoken, uc):
            created += 1

    stLogout(sessionMgt, csrftoken)

    writeLog('Created ' + str(created) + ' of ' + str(len(userClasses)) + ' user classes',
             'INFORMATION')
    writeLog('I issued: ' + str(apiCounter.value) + ' APIs on this run', 'INFORMATION')
    writeLog('Stopping at ' + str(datetime.datetime.now()), 'INFORMATION')
    if created != len(userClasses):
        sys.exit(1)
