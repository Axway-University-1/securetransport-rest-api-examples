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
# V2.00 Plamen Milenkov  08-Oct-2026  The export password is no longer put in the URL (servers and
#                                     proxies log a URL) and no longer printed: it comes from the
#                                     environment or a prompt and travels in the request body, with
#                                     the export operation of the reference (POST
#                                     /certificates/{id}/operations). The key file is written
#                                     readable by its owner only, and never over a file that is
#                                     there. No add-on library is needed any more. Every failure
#                                     exits 1, a missing id exits 2.
# V1.01 Ian Percival   20-Jun-2023 Fix typos
# V1.00 Ian Percival   24-Oct-2021 Python3
#
# This script accepts as input a Certificate ID and exports the certificate with its PRIVATE
# KEY, as a PKCS#12 file, to a file.
#
# APIs used - /myself ( ST login and logout )
#             /certificates/{id}/operations ( POST, operation=export )
#
# Usage: python3 stGetPrivateCert.py CERTIFICATE_ID [OUTPUT_FILE]
#
#        CERTIFICATE_ID  the id of the certificate to export (a private one, with a key)
#        OUTPUT_FILE     where to write it. Default: exportedPrivateKey.p12 in the current
#                        directory. The script will not overwrite a file that is there.
#
#        The password that protects the exported file is read from the environment variable
#        ST_EXPORT_PASSWORD, or asked for with a prompt that shows nothing. You choose it:
#        the server does not check it, it only protects the file.
#
# Risk: read - reads the server only, but it writes the private key of the certificate to a file on this machine
#
# Notes:
# - THE FILE HOLDS A PRIVATE KEY. It is written with mode 0600 (its owner only) and
#   exportedPrivateKey* is in the .gitignore of this repository. Delete it when you are done.
# - Confirmed directly (5.5-20260924): POST /certificates/{id}/operations?operation=export&format=pkcs12
#   with the password as a multipart form field (exportPassword) answers 200 with the
#   PKCS#12 file as application/octet-stream, and openssl reads the private key (a
#   "Shrouded Keybag") and the certificate out of it with that password. Without a
#   password it answers 400; with Accept: application/json, 406.
# - The earlier version used GET /certificates/{id}?exportPrivateKey=true&password=..., which
#   puts the password in the query string, and answers multipart/mixed.
# - Exit codes: 0 exported, 1 anything failed, 2 the certificate id is missing.
#
# Outputs:
#    The key file. A logile provides some information
#
# Start of Program is 'main' below.
#   Configuration section is there for you to tailor to your env...
#
# All functions are defined first below this header.

import base64
import datetime
import getpass
import os
import sys

import requests

from multiprocessing import Value
from requests.packages.urllib3.exceptions import InsecureRequestWarning
from urllib.parse import quote


#---------------------
# Supporting Functions
#---------------------

# Use a commin logFile in case running in batch etc
def writeLog(logString, severity):
    # This is the logfile for our python script
    print(logString)

    tstamp = datetime.datetime.now()
    inString = str(tstamp) + ' ' + severity + ' ' + logString + '\n'
    try:
        fHandle = open(logFile, 'a+')
        fHandle.write(inString)
        fHandle.close()
    except IOError:
        print('Problem writing to log')


# Send one request. Anything that keeps the call from completing is fatal: the script
# says what failed and exits 1. An HTTP status is not an exception, so the caller
# looks at it (see stExpect).
def stCall(session, method, url, **kwargs):
    try:
        response = getattr(session, method.lower())(url, verify=stVerify, timeout=stTimeout, **kwargs)
    except requests.exceptions.Timeout as et:
        writeLog('Timeout talking to ' + url + ': ' + str(et), 'FATAL')
        sys.exit(1)
    except requests.exceptions.ConnectionError as ec:
        writeLog('I cannot connect to ' + url + ': ' + str(ec), 'FATAL')
        sys.exit(1)
    except requests.exceptions.RequestException as e:
        writeLog('The request to ' + url + ' failed: ' + str(e), 'FATAL')
        sys.exit(1)
    numAPIs.value += 1
    return response


# Exit 1 unless the status is the one expected
def stExpect(response, expected, what):
    if response.status_code != expected:
        writeLog(what + ' answered ' + str(response.status_code) + ', not ' + str(expected) +
                 ': ' + str(response.text)[:300], 'FATAL')
        sys.exit(1)


# The password for the exported file: the environment, else a prompt that shows nothing
def stGetExportPassword():

    password = os.environ.get('ST_EXPORT_PASSWORD', '')
    if not password:
        try:
            password = getpass.getpass('Password to protect the exported private key: ')
        except (EOFError, KeyboardInterrupt):
            password = ''
    if not password:
        print('I need a password to protect the exported key: set ST_EXPORT_PASSWORD, or type one at the prompt.')
        sys.exit(2)
    return password


# Write the key file: new, and readable by its owner only. It is not written over a file that is there.
def stWriteKeyFile(path, content):

    try:
        descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    except FileExistsError:
        writeLog('The file ' + path + ' is there already. Remove it, or give another name.', 'FATAL')
        sys.exit(1)
    except OSError as e:
        writeLog('I cannot write ' + path + ': ' + str(e), 'FATAL')
        sys.exit(1)
    with os.fdopen(descriptor, 'wb') as f:
        f.write(content)


def stExportCert(session, token, certId, password, pkeyfile):

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/octet-stream'}

    # The password goes in the body, as a multipart form field, not in the URL
    url = stUrl + 'certificates/' + quote(certId) + '/operations?operation=export&format=pkcs12'

    response = stCall(session, 'POST', url, headers=headers, files={'exportPassword': (None, password)})
    stExpect(response, 200, 'Exporting the certificate')

    if not response.content:
        writeLog('The export answered with no file', 'FATAL')
        sys.exit(1)

    stWriteKeyFile(pkeyfile, response.content)
    print('Private Key exported with filename ' + pkeyfile + ', protected by the password you gave')


# Login to ST using session management, and return the csrfToken the server answers with
#
# This is the ST api/v2.0/myself POST method
#
def stLogin(basicAuth, session):

    url = stUrl + 'myself'

    authString = 'Basic ' + basicAuth
    # If using Certiificate auth
    #headers = {'Referer': referer,
    #          'Accept': 'application/json'}

    headers = {'Referer': referer,
               'Accept': 'application/json',
               'Authorization': authString}

    response = stCall(session, 'POST', url, headers=headers)
    stExpect(response, 200, 'Login')

    # Successful login
    # {
    #     "message" : "Logged in"
    # }
    if response.json().get('message') != 'Logged in':
        writeLog('The login did not answer "Logged in"', 'FATAL')
        sys.exit(1)
    writeLog('Session Mgt Login', 'SUCCESS')
    # Present from the 20230525 release, and to be sent back on every later call
    return response.headers.get('csrfToken')


# This is the ST logout session management
#
# This is the ST api/v2.0/myself DELETE method
#
def stLogout(session, token):

    url = stUrl + 'myself'

    headers = {'Referer': referer,
               'csrfToken': token,
               'Accept': 'application/json'}

    response = stCall(session, 'DELETE', url, headers=headers)
    stExpect(response, 200, 'Logout')

    # Successful logout
    # {
    #     "message" : "Logged out"
    # }
    writeLog('Logged Out', 'SUCCESS')
    return True


#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
#++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
#====================================================================================

if __name__ == "__main__":

    try:
        certId = sys.argv[1]
    except IndexError:
        print('Please provide argument 1 - the certificate ID you wish to export')
        print('Usage: python3 stGetPrivateCert.py CERTIFICATE_ID [OUTPUT_FILE]')
        sys.exit(2)

    #--------------------------------------------------------------------------------
    # BEGIN Configuration Section
    #--------------------------------------------------------------------------------
    # Please modify the below to match your environment

    stTimeout = 120

    logFile = 'my.log'
    referer = 'THIS_IS_A_RANDOM_TEXT'
    pkeyfile = sys.argv[2] if len(sys.argv) > 2 else 'exportedPrivateKey.p12'

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

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    # The password and the file are looked at before anything is sent to the server
    exportPassword = stGetExportPassword()
    if os.path.exists(pkeyfile):
        print('The file ' + pkeyfile + ' is there already. Remove it, or give another name.')
        sys.exit(1)

    outputString = 'Starting at ' + str(datetime.datetime.now())
    writeLog(outputString, 'INFORMATION')

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Before we do anything, lets authenticate to ST
    # We'll use session management as this avoids having to authenticate on every API call
    sessionMgt = requests.Session()

    # If you wish to use Certificate authentication create an unencrypted private key + cert file
    # sessionMgt.cert = certificatePath

    csrftoken = stLogin(basicAuth, sessionMgt)

    stExportCert(sessionMgt, csrftoken, certId, exportPassword, pkeyfile)

    # Completion Section
    stLogout(sessionMgt, csrftoken)
    infoText = 'Completed Run. Number of APIs issued: ' + str(numAPIs.value)
    writeLog(infoText, 'INFORMATION')
