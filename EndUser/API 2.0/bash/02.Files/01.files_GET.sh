#!/bin/bash
# ==============================================================================
# Script Name: 01.files_GET.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script lists the files in the user's home folder using the `/files`
# endpoint.
# It demonstrates reusing the session from the cookie jar. For the query
# parameters - paging, sorting, metadata, hidden files, glob patterns - see
# 09.files_GET_query.sh.
#
# Usage:
# ./01.files_GET.sh
#
# Risk: read
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - A session must already exist. Run 01.Authenticate/01.myself_POST.sh first.
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put the values for your own environment in set_variables.local.sh.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

COOKIE="${SCRIPT_DIR}/../myCookie.jar"

#
# Curl command to list all files under the user's home folder, including the home folder name
# It is assumed a session login took place prior to this via 01.Authenticate/01.myself_POST.sh
# Session cookies are read from a file called myCookie.jar
# Exits 1 when the server refuses.
#
result=$(curl -L -b "${COOKIE}" -w "\n%{http_code}" -s -k -X GET "${ST_URL}/files" -H "accept: application/json" -H "Referer: THIS_IS_A_RANDOM_TEXT")
http_status=${result##*$'\n'}
printf '%s\n' "${result%$'\n'*}"
if [[ $http_status -ne 200 ]] ; then
    printf "List failure: %s\n" "${http_status}"
    exit 1
fi

printf "Files successfully listed\n"

# 
# As a next step try to filter the results by using the query parameters
# limit - The number of results to return
# offset - The number of results to skip
# sortBy - The field to sort the results by (fileName, lastModifiedTime, size)
# order - The order to sort the results by (ASC, DESC)
# transferMode - The transfer mode of the file (ASCII, BINARY)
# metadata - The metadata to return with the file (true, false)
# showdots - Whether to show hidden files (true, false)
#