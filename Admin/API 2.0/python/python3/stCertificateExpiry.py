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
# V1.00 Plamen Milenkov  15-Sep-2025  Replaces utils/stSTANCertificateExpiry.py.
#                                     That file claimed to count certificates and
#                                     report expirations, but it was a copy of the
#                                     configuration compare tool with the header
#                                     changed: it read two variables that were
#                                     never assigned and would fail immediately.
#                                     There was nothing to convert, so this is a
#                                     working implementation of what it described,
#                                     reading the live API rather than an XML
#                                     export. CSRF compliant.
#
# This script counts the certificates on the system and reports the ones that
# have expired or are about to.
#
# Certificate expiry monitoring is one of the most useful things to automate:
# an expired trusted certificate breaks partner transfers with an error that
# rarely points at the real cause.
#
# A note on the expiry field
# --------------------------
# The name of the field that carries the expiry date has varied between
# releases, so rather than assume one, this script looks for the first of
# several likely names in the response and tells you which it found. If it
# cannot find one, it prints the fields that are actually present so that you
# can set expiryFieldName in the configuration section. Check your own version
# in the Open API page at:
#
#    https://<SERVER>:8444/api/v2.0/docs/index.html
#
# APIs used - /myself ( ST login and logout ) POST, DELETE
#             /certificates  GET
#
# Usage: python3 stCertificateExpiry.py [DAYS]
#
#        DAYS - warn about certificates expiring within this many days.
#               Defaults to the warnWithinDays setting below.
#
# Outputs:
#    A count by usage, then the expired and expiring certificates, on standard
#    output. This script only reads. It changes nothing.
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
        if 'Logged in' == jsonResponse.get('message'):
            print('Session Login')
            return csrftoken
        else:
            print('Login Failure ', response.status_code)
            sys.exit(1)


# Work out which field carries the expiry date.
#
# Returns the field name, or None when none of the candidates are present.
#
def findExpiryField(certificate):

    if expiryFieldName:
        return expiryFieldName if expiryFieldName in certificate else None

    for candidate in expiryFieldCandidates:
        if candidate in certificate and certificate.get(candidate) is not None:
            return candidate
    return None


# Turn whatever the API gave us into a date.
#
# Different releases have used an ISO 8601 string and an epoch value in
# milliseconds, so both are handled. Returns None if the value cannot be read.
#
def parseExpiry(value):

    if value is None:
        return None

    # An epoch value, in seconds or milliseconds
    if isinstance(value, (int, float)):
        seconds = value / 1000.0 if value > 100000000000 else float(value)
        try:
            return datetime.datetime.utcfromtimestamp(seconds)
        except (ValueError, OverflowError, OSError):
            return None

    text = str(value).strip()
    if not text:
        return None

    # A string of digits is still an epoch value
    if text.isdigit():
        return parseExpiry(int(text))

    # ISO 8601, with or without the trailing Z
    isoText = text.replace('Z', '+0000')
    for fmt in ('%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%dT%H:%M:%S.%f%z',
                '%Y-%m-%dT%H:%M:%S', '%Y-%m-%d %H:%M:%S', '%Y-%m-%d'):
        try:
            parsed = datetime.datetime.strptime(isoText, fmt)
            return parsed.replace(tzinfo=None)
        except ValueError:
            continue

    return None


# Fetch every certificate, a page at a time
#
def stReadCertificates(session, csrftoken):

    certificates = []

    entry = 0
    numberObjectsToFetchPerCall = 200
    keepLooping = True

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    while keepLooping:

        url = (stUrl + 'certificates?offset=' + str(entry) +
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
                print('GET certificates returned ' + str(response.status_code))
                print(str(response.text))
                sys.exit(1)

            page = response.json()

            returnCount = page.get('resultSet', {}).get('returnCount', 0)
            if returnCount < numberObjectsToFetchPerCall:
                keepLooping = False

            certificates.extend(page.get('result', []))

            entry += numberObjectsToFetchPerCall

    return certificates


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import datetime
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

    # Report certificates expiring within this many days
    warnWithinDays = 90

    # Leave empty to let the script find the expiry field, or set it to the
    # field name your version uses to skip the guessing.
    expiryFieldName = ''

    # Tried in order, when expiryFieldName is empty
    expiryFieldCandidates = ['endDate', 'validTo', 'notAfter', 'expiryDate',
                             'expirationDate', 'certificateEndDate']

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

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

    # An optional command line override of the warning window
    if len(sys.argv) > 1:
        try:
            warnWithinDays = int(sys.argv[1])
        except ValueError:
            print('DAYS must be a whole number of days')
            sys.exit(0)

    numAPIs = Value('i', 0)                  # counter to see how many APIs we sent

    # We are turning off Cert validation - stop the warning messages
    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    certificates = stReadCertificates(sessionMgt, csrftoken)

    print('')
    print('Total certificates: ' + str(len(certificates)))

    if not certificates:
        stLogout(sessionMgt, csrftoken)
        print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
        sys.exit(0)

    # Count by usage, which is how the admin UI groups them
    byUsage = {}
    for cert in certificates:
        usage = str(cert.get('usage', 'unknown'))
        byUsage[usage] = byUsage.get(usage, 0) + 1

    for usage in sorted(byUsage):
        print('   ' + usage + ': ' + str(byUsage[usage]))

    # Which field holds the expiry date?
    expiryField = findExpiryField(certificates[0])

    if expiryField is None:
        print('')
        print('I could not find an expiry date field on the certificates.')
        print('I looked for: ' + ', '.join(expiryFieldCandidates))
        print('')
        print('These are the fields the API returned for the first certificate:')
        for key in sorted(certificates[0].keys()):
            print('   ' + str(key) + ' = ' + str(certificates[0].get(key)))
        print('')
        print('Set expiryFieldName in the configuration section to the right one.')
        stLogout(sessionMgt, csrftoken)
        print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
        sys.exit(0)

    print('')
    print('Reading the expiry date from the ' + expiryField + ' field')

    now = datetime.datetime.utcnow()
    horizon = now + datetime.timedelta(days=warnWithinDays)

    expired = []
    expiring = []
    unreadable = []

    for cert in certificates:
        when = parseExpiry(cert.get(expiryField))
        if when is None:
            unreadable.append(cert)
        elif when < now:
            expired.append((when, cert))
        elif when <= horizon:
            expiring.append((when, cert))

    def describe(cert):
        parts = []
        for field in ('name', 'subject', 'account', 'usage', 'id'):
            if cert.get(field):
                parts.append(field + '=' + str(cert.get(field)))
        return ', '.join(parts)

    print('')
    print('=' * 70)
    print('EXPIRED: ' + str(len(expired)))
    print('=' * 70)
    for when, cert in sorted(expired):
        print(when.strftime('%Y-%m-%d') + '  (' + str((now - when).days) + ' days ago)')
        print('   ' + describe(cert))

    print('')
    print('=' * 70)
    print('EXPIRING within ' + str(warnWithinDays) + ' days: ' + str(len(expiring)))
    print('=' * 70)
    for when, cert in sorted(expiring):
        print(when.strftime('%Y-%m-%d') + '  (in ' + str((when - now).days) + ' days)')
        print('   ' + describe(cert))

    if unreadable:
        print('')
        print('I could not read the expiry date of ' + str(len(unreadable)) + ' certificate(s):')
        for cert in unreadable:
            print('   ' + describe(cert) +
                  '  ' + expiryField + '=' + str(cert.get(expiryField)))

    stLogout(sessionMgt, csrftoken)
    print('')
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
