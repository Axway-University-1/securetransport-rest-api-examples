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
# V1.01 Ian Percival   20-Jun-2023 Fix typos 
# V1.00 Ian Percival   24-Oct-2021 Python3 
#
# This script accepts as input a Certificate ID and outputs the cert to a file
#
# NOTE we are using an Add-on Pythin library - requests-toolbox which is not part of the
# standard python installation.  Multipart parsing is always a bit of a pain!
# (python3 -m pip install requests_toolbelt)
#
# APIs used - /myself ( ST login and logout )
#             /certificates ( GET )
#
# Inputs:
#    ./stGetPrivateCert.py ID
#
# Outputs:
#    A logile provides some information
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#
# All functions are defined first below this header.


#---------------------
# Supporting Functions
#---------------------

# Use a commin logFile in case running in batch etc
def writeLog(logString, severity):
    # This is the logfile for our python script
    global logFile
    print( logString)


    tstamp = datetime.datetime.now()
    if severity == 'SUCCESS':
        inString = str(tstamp) + ' ' +  severity + '     ' + logString + '\n'
    elif severity == 'WARNING':
        inString = str(tstamp) + ' ' +  severity + '     ' + logString + '\n'
    else:
        inString = str(tstamp) + ' ' +  severity + ' ' + logString + '\n'
    try:
        fHandle = open(logFile,'a+')
        fHandle.write(inString)
        fHandle.close()
    except:
        print( 'Problem writing to log' )
        return

    return


def stExportCert(apiCounter, certId, pkeyfile):

    global csrftoken
    global referer
    global sessionMgt
    global stTimeout
    global stUrl


    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'multipart/mixed'}

    url = stUrl + 'certificates/' + certId + '?password=12345678&exportPrivateKey=true'

    try:
        response = sessionMgt.get(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        writeLog('I cannot connect to ' + stUrl, 'FATAL')
        writeLog(str(ec),'FATAL')
        sys.exit(1)
    except requests.exceptions.HTTPError as eh:
        writeLog('HTTP Error','FATAL')
        sys.exit(1)
    except requests.exceptions.Timeout as et:
        writeLog('Timeout Error:' + str(et),'FATAL')
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        writeLog('Unknown Error:' + str(e),'FATAL')
        sys.exit(1)
    else:
        apiCounter.value+=1
        print (response.status_code)
        #print(str(response.content))


        multiData = decoder.MultipartDecoder.from_response(response)
        for part in multiData.parts:
            if 'application/octet-stream' in str(part.headers):


                f = open(pkeyfile,"wb")
                f.write(part.content)
                f.close()

        print("Private Key exported with filename " + pkeyfile + " password 12345678")
    return




# Login to ST using session management
#
# This is the ST api/v1.4/myself POST method
#
def stLogin(basicAuth):

    global csrftoken
    global referer
    global sessionMgt
    global stTimeout
    global stUrl

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth
    # If using Certiificate auth
    #headers = {'Referer': referer,
    #          'Accept': 'application/json'}


    headers = {'Referer': referer,
              'Accept': 'application/json',
              'Authorization': authString}

    try:
        response = sessionMgt.post(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        writeLog('I cannot connect to ' + stUrl,'FATAL')
        writeLog(str(ec),'FATAL')
        sys.exit(1)
    except requests.exceptions.HTTPError as eh:
        writeLog('HTTP Error','FATAL')
        raise SystemExit(eh)
    except requests.exceptions.Timeout as et:
        writeLog('Timeout Error:' + str(et), 'FATAL')
        raise SystemExit(et)
    except requests.exceptions.RequestException as e:
        raise SystemExit(e)
    else:
        writeLog('Session Mgt Login','SUCCESS')
        #print( response.status_code )
        #print( response.json())

        # Successful login

        # {
        #     "message" : "Logged in"
        # }
        csrftoken = response.headers.get('csrfToken')
        return True
    return True


# This is the ST logout session management
#
# This is the ST api/v1.4/myself DELETE method
#
def stLogout():

    global csrftoken
    global referer
    global sessionMgt
    global stTimeout
    global stUrl

    url = stUrl + 'myself'

    headers = {'Referer': referer,
              'csrfToken': csrftoken,
              'Accept': 'application/json'}
    try:
        response = sessionMgt.delete(url, headers=headers, verify=False, timeout=stTimeout)
    except requests.ConnectionError as ec:
        writeLog('I cannot connect to ' + stUrl, 'FATAL')
        writeLog(str(ec),'FATAL')
        sys.exit(1)
    except requests.exceptions.HTTPError as eh:
        writeLog('HTTP Error','FATAL')
        raise SystemExit(eh)
    except requests.exceptions.Timeout as et:
        writeLog('Timeout Error:' + str(et),'FATAL')
        raise SystemExit(et)
    except requests.exceptions.RequestException as e:
        raise SystemExit(e)
    else:
        writeLog('Logged Out','SUCCESS')
        return True

        # Successful logout

        # {
        #     "message" : "Logged out"
        # }




#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#====================================================================================

if __name__ == "__main__":

    import base64
    import datetime
    import json
    import multiprocessing
    import os
    import requests
    import requests_toolbelt  # NOTE THIS IS NOT PART OF STANDARD PYTHON INSTALLATION
    import ssl
    import string
    import sys

    from multiprocessing import Queue
    from multiprocessing import Process
    from multiprocessing import Value

    from requests.packages.urllib3.exceptions import InsecureRequestWarning
    from requests_toolbelt.multipart import decoder # See NOTE above

    global csrftoken
    global logFile
    global referer
    global sessionMgt
    global stTimeout
    global stUrl


    #--------------------------------------------------------------------------------
    # BEGIN Configuration Section
    #--------------------------------------------------------------------------------
    # Please modify the below to match your environment


    # define how many parallel procs we will create
    numberParallelProcs = 10
    stTimeout = 120

    logFile='my.log'
    referer = 'THIS_IS_A_RANDOM_TEXT'
    pkeyfile = 'exportedPrivateKey'

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

    try:
        certId = sys.argv[1]
    except IndexError:
        errText = 'Please provide argument 1 - the certificate ID you wish to export'
        print(errText)
        sys.exit(0)


    APICounter = Value('i',0)


    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')


    logEntry = 'Number of CPUs available to this server: ' + str(multiprocessing.cpu_count())
    writeLog( logEntry, 'INFORMATION')

    logEntry = 'Commencing Run Using ' + str(numberParallelProcs) + ' threads\n'
    writeLog( logEntry, 'INFORMATION')





    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    #  and we plan to issue potentially millions of APIs!
    # Now create our session....
    sessionMgt = requests.Session()

    # If you wish to use Certificate authentication create an unencrypted private key + cert file
    # sessionMgt.cert = certificatePath

    # We are turning off Cert validation - stop the warning messages
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)




    # Now use Session Management

    if not stLogin(basicAuth):
        print("Something nasty! Couldn't login to ST")
        sys.exit(0)
    APICounter.value += 1


    # We won't use multiprocessing here as we are not doing too much
    # 
    stExportCert(APICounter, certId, pkeyfile)

    # Completion Section

    stLogout()
    APICounter.value+=1
    infoText = 'Completed Run. Number of APIs issued: ' + str(APICounter.value)
    writeLog( infoText, 'INFORMATION')



#------------------------------------------------------------------------------------
#

