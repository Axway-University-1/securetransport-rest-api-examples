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
# V1.00 Plamen Milenkov   05-Oct-2026
#
# This script counts the billable transfers per calendar day, for the last few
# days, for every account or for one. Read only.
#
# SecureTransport 5.5-20260924 or later classifies each transfer as billable or
# not. A transfer from before that release has no billable status, so it is not
# counted. Features/audit-billable-transfers explains which transfers are
# billable.
#
# Usage:
#    python3 stBillableTransfers.py [DAYS [ACCOUNT]]
#
#    DAYS     how many days to count, today included (default reportDays below)
#    ACCOUNT  count only this account's transfers (default accountName below,
#             empty for every account)
#
# APIs used - /myself         POST DELETE ( ST login and logout )
#             /logs/transfers GET, with isBillable=true
#
# Risk: read
#
# Notes:
# - Exit codes: 0 done, 1 anything failed, 2 the arguments are wrong.
#
# Outputs:
#    One line per day, today last, and the total.
#
# Each day runs from midnight to midnight in this machine's time zone, and is
# sent in RFC 2822, for example 'Mon, 05 Oct 2026 00:00:00 +0300'.
#
# The count is resultSet.totalCount. On /logs/transfers, resultSet.returnCount
# is capped by limit, which is 1 here to keep each response small, so reading
# returnCount would count at most 1 a day.
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
        response = session.delete(url, headers=headers, verify=stVerify, timeout=stTimeout)
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
        numAPIs.value += 1
        if response.status_code != 200:
            print('Logout answered ' + str(response.status_code))
            sys.exit(1)
        print('Session Mgt Logged Out')
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
        numAPIs.value+=1
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


# The calendar days to count, oldest first, as (label, start, end). Each start
# and end is a local midnight, with its own UTC offset, so a day that crosses a
# daylight saving change still runs from midnight to midnight.
#
def dayWindows(days, today=None):

    today = today or datetime.date.today()
    windows = []
    for offset in range(days - 1, -1, -1):
        day = today - datetime.timedelta(days=offset)
        start = datetime.datetime.combine(day, datetime.time()).astimezone()
        end = datetime.datetime.combine(day + datetime.timedelta(days=1), datetime.time()).astimezone()
        windows.append((day.isoformat(), start, end))
    return windows


# The number of billable transfers that started and ended within one window.
# Returns None when the server's answer holds no count.
#
# This is the ST /logs/transfers GET method
#
def stCountBillable(session, csrftoken, start, end, account):

    params = {'isBillable': 'true',
              'startTimeAfter': email.utils.format_datetime(start),
              'endTimeBefore': email.utils.format_datetime(end),
              'limit': '1',
              'fields': 'id'}
    if account:
        # account=, not accountName=, which this endpoint silently ignores
        params['account'] = account

    url = stUrl + 'logs/transfers?' + urllib.parse.urlencode(params)

    headers = {'Referer': referer,
               'csrfToken': csrftoken,
               'Accept': 'application/json'}

    try:
        response = session.get(url, headers=headers, verify=stVerify, timeout=stTimeout)
    except requests.ConnectionError as ec:
        print('I cannot connect to ' + url + ' ' + str(ec))
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
        numAPIs.value += 1
        if response.status_code != 200:
            # a day with no count would make the report wrong, so this is not carried on from
            print('GET logs/transfers answered ' + str(response.status_code) + ': ' + str(response.text)[:300])
            sys.exit(1)
        # totalCount, not returnCount, which limit caps at 1
        return response.json().get('resultSet', {}).get('totalCount')


def stReportBillable(session, csrftoken, days, account):

    print('Billable transfers per day, for ' + (account or 'every account'))

    total = 0
    unread = 0
    for label, start, end in dayWindows(days):
        count = stCountBillable(session, csrftoken, start, end, account)
        if count is None:
            print('  ' + label + '  could not read a count')
            unread += 1
            continue
        print('  ' + label + '  ' + str(count))
        total += int(count)

    print('Total: ' + str(total) + ' billable transfer(s) in ' + str(days) + ' day(s)')
    if unread:
        print('INCOMPLETE: the answer of ' + str(unread) + ' day(s) held no count, so that total is too low.')
        sys.exit(1)
    return total

# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import base64
    import datetime
    import email.utils
    import os
    import requests
    import sys
    import urllib.parse

    from multiprocessing import Value
    from requests.packages.urllib3.exceptions import InsecureRequestWarning



    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment


    stTimeout = 120  # in seconds
    referer = 'THIS_IS_A_RANDOM_TEXT'
    reportDays = 7     # how many days to count, today included
    accountName = ''   # one account's transfers only, or '' for every account

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

    # The command line, when given, wins over the configuration above
    if len(sys.argv) > 3 or (len(sys.argv) > 1 and not sys.argv[1].isdigit()) \
            or (len(sys.argv) > 1 and int(sys.argv[1]) < 1):
        print('Usage: python3 stBillableTransfers.py [DAYS [ACCOUNT]]')
        print('DAYS is a whole number, 1 or more.')
        sys.exit(2)
    if len(sys.argv) > 1:
        reportDays = int(sys.argv[1])
    if len(sys.argv) > 2:
        accountName = sys.argv[2]

    numAPIs = Value('i', 0)                  # counter to see how many APIS we sent

    # We are turning off Cert validation - stop the warning messages
    if not stVerify:
        requests.packages.urllib3.disable_warnings(InsecureRequestWarning)

    # Now create our session....
    sessionMgt = requests.Session()

    # We'll use session management and login to ST via /myself
    csrftoken = stLogin(basicAuth, sessionMgt)

    stReportBillable(sessionMgt, csrftoken, reportDays, accountName)

    # Completion Section

    stLogout(sessionMgt,csrftoken)
    print('Completed Run, number of APIs issued: ' + str(numAPIs.value))
