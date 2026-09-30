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
# V2.00 Plamen Milenkov  15-Sep-2025  Converted from python2. The comparison now
#                                     runs in both directions, so the order of
#                                     the two files no longer matters.
# V1.00 Ian Percival     07-Aug-2020
#
# Tool to compare two server Configuration XMLs looking for parameter differences.
# Useful when you have no access to the system to use the APIs.
#
# Export the system configuration via the GUI. By default it places a zip file
# in /var/tmp. Extract just the config xml with:
#
#    unzip -j export_configuration.zip systemConfiguration.xml -d /home/axway/api
#
# Use the output XML file as input to this program.
#
# APIs used - None. This is an XML processor.
#
# Usage:
#    python3 stCompareExportedConfigurations.py filename1 filename2
#
# Outputs:
#    The differences, on standard output, in three groups: options whose value
#    differs, options only in the first file, and options only in the second.
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


# Read every option out of an exported systemConfiguration.xml and return it as
# a dictionary of option name to value.
#
# An option that is present but carries no value is recorded as 'Not Specified',
# so that it can be told apart from an option that is missing altogether.
#
def extractXMLparams(config, sourceFile):

    try:
        xmlTree = ET.parse(sourceFile)
    except IOError:
        print('I cannot read the file: ' + str(sourceFile))
        sys.exit(1)
    except ET.ParseError as e:
        print('The file ' + str(sourceFile) + ' is not valid XML: ' + str(e))
        sys.exit(1)

    # ConfigurationModel
    root1 = xmlTree.getroot()

    for opt in root1.findall('options'):
        for opt2 in opt.findall('option'):
            for opt3 in opt2.findall('optionItem'):
                optName = None
                optValue = None
                for child in opt3:
                    if child.tag == 'name':
                        optName = child.text
                    if child.tag == 'value':
                        optValue = child.text
                if optName is None:
                    continue
                if optValue is None:
                    config[optName] = 'Not Specified'
                else:
                    config[optName] = optValue

    return config


# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# MAIN = Start of Program....
# ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
# ====================================================================================

if __name__ == "__main__":

    import datetime
    import os
    import sys
    import xml.etree.ElementTree as ET

    # --------------------------------------------------------------------------------
    # BEGIN Configuration Section
    # --------------------------------------------------------------------------------
    # Please modify the below to match your environment

    # The log file is written next to this script
    logFile = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'compareXML.log')

    # -------------------------------------------------------------------------------
    # END Configuration Section
    # -------------------------------------------------------------------------------

    # READ in the command line arguments
    try:
        sourceFile1 = sys.argv[1]
    except IndexError:
        print('Please enter the Filename of the first exported Server Config XML')
        print('Usage: python3 stCompareExportedConfigurations.py filename1 filename2')
        sys.exit(0)

    try:
        sourceFile2 = sys.argv[2]
    except IndexError:
        print('Please enter the Filename of the second exported Server Config XML')
        print('Usage: python3 stCompareExportedConfigurations.py filename1 filename2')
        sys.exit(0)

    writeLog('Starting at ' + str(datetime.datetime.now()), 'INFORMATION')

    config1 = extractXMLparams({}, sourceFile1)
    config2 = extractXMLparams({}, sourceFile2)

    writeLog('File 1 ' + str(sourceFile1) + ' has ' + str(len(config1)) + ' options', 'INFORMATION')
    writeLog('File 2 ' + str(sourceFile2) + ' has ' + str(len(config2)) + ' options', 'INFORMATION')

    #
    # Compare in both directions. The python2 version of this tool only walked
    # the larger file and asked you to run it again with the arguments swapped,
    # which meant an option present only in the second file was never reported.
    #
    differentValue = []
    onlyInFirst = []
    onlyInSecond = []

    for name in sorted(config1):
        if name not in config2:
            onlyInFirst.append(name)
        elif config1[name] != config2[name]:
            differentValue.append(name)

    for name in sorted(config2):
        if name not in config1:
            onlyInSecond.append(name)

    print('')
    print('Options whose value differs: ' + str(len(differentValue)))
    print('-' * 70)
    for name in differentValue:
        print(name)
        print('   file 1: ' + str(config1[name]))
        print('   file 2: ' + str(config2[name]))

    print('')
    print('Options only in ' + str(sourceFile1) + ': ' + str(len(onlyInFirst)))
    print('-' * 70)
    for name in onlyInFirst:
        print(name + ' = ' + str(config1[name]))

    print('')
    print('Options only in ' + str(sourceFile2) + ': ' + str(len(onlyInSecond)))
    print('-' * 70)
    for name in onlyInSecond:
        print(name + ' = ' + str(config2[name]))

    # Completion Section
    print('')
    writeLog('Completed Run. ' + str(len(differentValue)) + ' differing, ' +
             str(len(onlyInFirst)) + ' only in file 1, ' +
             str(len(onlyInSecond)) + ' only in file 2.', 'INFORMATION')

# ------------------------------------------------------------------------------------
#
