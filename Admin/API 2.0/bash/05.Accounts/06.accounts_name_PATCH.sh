#!/bin/bash
# ==============================================================================
# Script Name: 06.accounts_name_PATCH.sh
# Author: Plamen Milenkov
# Created: 2025-09-15
# Location: Sofia
# ==============================================================================
# Description:
# This script performs partial updates to an account using the
# `/accounts/{name}` endpoint with the PATCH method.
#
# The PATCH method has three types of operations: add, remove, and replace.
# It demonstrates:
# - Replacing a single field
# - Replacing two fields in one request
# - Removing a field
# - Adding an element to an array
#
# Usage:
# ./06.accounts_name_PATCH.sh
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The add operation is best suited for arrays. You can use it to add a new
#   element to an empty or non-empty array.
# - The path "/addressBookSettings/policy" means that there is a first level
#   property named "addressBookSettings" with a property named "policy" under it.
# - From the schema, the policy can be "default", "custom" or "disabled".
# ==============================================================================

#
# Get the directory of the script
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

# 
# First we will load the variables into our context.
# Put your own values in set_variables.local.sh, which set_variables.sh
# loads and which git ignores.
#
printf "Loading variables into our context..."
source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"

# The PATCH Method has 3 types of operations: add, remove, and replace.

# OPERATION = ADD
# The add operation is best suited for arrays. You can use it to add a new element to an empty or non-empty array.

# In our first example, lets add an element to the "addressBookSettings.sources" array.
# The syntax "addressBookSettings.sources" means that there is a first level property named "addressBookSettings"
# and under that object, there is a property named "sources".

ACCOUNT="john"

# The result will be in the following format:
# ...
# "addressBookSettings" : {
#     "policy" : "default",
#     "nonAddressBookCollaborationAllowed" : null,
#     "sources" : [ {
#       "id" : "8a050087950494eb0195049650c60000",
#       "name" : "LDAP",
#       "type" : "LDAP",
#       "parentGroup" : "LDAP",
#       "enabled" : true,
#       "customProperties" : {
#         "MaxPageEntries" : "100",
#         "ldapDomainName" : "Logged In (current user domain)"
#       }
#     }, {
#       "id" : "8a050087950494eb01950496545d0002",
#       "name" : "Local",
#       "type" : "LOCAL",
#       "parentGroup" : "Local",
#       "enabled" : true,
#       "customProperties" : {
#         "buType" : "allBU"
#       }
#     } ],
#     "contacts" : [ ]
#   }
# ...
# We will use the replace operation on policy. 
# From the schema we can see that the policy can be "default", "custom" or "disabled".
# We will change the policy to "custom". 
# ...


printf "Getting the account %s and filtering only the addressBookSettings...\n" "${ACCOUNT}"
curl -k -u ${ST_USER}:${ST_PASSWORD}  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}?type=user&fields=addressBookSettings.policy,addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "${REFERER_HEADER}"

printf "Changing the policy to custom...\n"
curl -k -u ${ST_USER}:${ST_PASSWORD}  -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d '[
  {
    "op": "replace",
    "path": "/addressBookSettings/policy",
    "value": "custom"
  }
  ]'

# Now let's repeat the querry, but this time try to modify two parameters at once.
printf "Changing two fields at the same time...\n"
curl -k -u ${ST_USER}:${ST_PASSWORD}  -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d '[
  {
    "op": "replace",
    "path": "/addressBookSettings/policy",
    "value": "default"
  },
  {
    "op": "replace",
    "path": "/addressBookSettings/nonAddressBookCollaborationAllowed",
    "value": "true"
  }
  ]'

printf "Removing the addressBookSettings.nonAddressBookCollaborationAllowed...\n"
curl -k -u ${ST_USER}:${ST_PASSWORD}  -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d '[
  {
    "op": "remove",
    "path": "/addressBookSettings/nonAddressBookCollaborationAllowed"
  }
  ]'

printf "Checking the result...\n"
curl -k -u ${ST_USER}:${ST_PASSWORD}  -X GET "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}?type=user&fields=addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "${REFERER_HEADER}"

printf "Adding a new contact...\n"
# "-" appends to the end of the array, whether it is empty or already has
# entries - a numeric index like "1" only works if the array already has an
# element at index 0, confirmed against a real server: it 400s with "Array
# index 1 out of bounds" on a freshly created account with no contacts yet.
curl -k -u "${ST_USER}:${ST_PASSWORD}"  -X PATCH "https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts/${ACCOUNT}" -H "accept: */*" -H "${REFERER_HEADER}" -H 'Content-Type: application/json' -d '[
  {
    "op": "add",
    "path": "/addressBookSettings/contacts/-",
    "value": {
      "fullName": "Jane Doe",
      "primaryEmail": "jane.doe@abc.com"
    }
}]'