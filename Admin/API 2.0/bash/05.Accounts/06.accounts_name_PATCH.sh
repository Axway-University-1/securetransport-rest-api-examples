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
# ./06.accounts_name_PATCH.sh [NAME]
#
#   NAME  the user account (default example_user, the one 02.accounts_POST.sh creates)
#
# Risk: write
#
# Notes:
# - Ensure that `set_variables.sh` is correctly configured and sourced.
# - The add operation is best suited for arrays. You can use it to add a new
#   element to an empty or non-empty array.
# - The path "/addressBookSettings/policy" means that there is a first level
#   property named "addressBookSettings" with a property named "policy" under it.
# - From the schema, the policy can be "default", "custom" or "disabled".
# - It changes the address book settings of the account and leaves a contact in them. It first reads and prints the old settings, then the body that puts the policy and the flag
#   back, and afterwards the one that takes the contact out again. Deleting the account (07.accounts_name_DELETE.sh) removes all of it.
# - The change to "custom" is only tried when the account has at least two address book sources; it is refused otherwise (400 "addressBookSettings.sources must be at least two."),
#   and the script says it skips it. The accounts this lab creates have the two (LDAP and Local), and a plain 204 follows.
# - Requires `jq`, which reads the settings and builds each patch.
# - "-" appends to the end of an array, empty or not; a numeric index like "1" only works when index 0 is taken (400 "Array index 1 out of bounds").
# - Confirmed directly: each PATCH answers 204 with no body. `remove` of `nonAddressBookCollaborationAllowed` answers 204 and the field reads back null (it stays in the object).
#   The value "true" and the boolean true are both accepted and read back as true. A path that does not exist is 400 `Missing field "nope"`, and on a service account the
#   address book settings do not exist (400 `Missing field "addressBookSettings"`).
# - Exit codes: 0 when every call answered as expected, 1 when the account cannot be read or the server refuses a patch (the later ones are not sent).
# ==============================================================================

#
# Get the directory of this script, so that it can be run from any location
#
SCRIPT_DIR=$(dirname "$(realpath "$0")")

source "${SCRIPT_DIR}/../set_variables.sh"

REFERER_HEADER="Referer: THIS_IS_A_RANDOM_TEXT"
MAIN_URL="https://${ST_SERVER}:${ST_PORT}/api/v2.0/accounts"
NAME="${1:-example_user}"
NAME_URI=$(jq -rn --arg name "${NAME}" '$name | @uri')
ACCOUNT_URL="${MAIN_URL}/${NAME_URI}"

# patch DESCRIPTION BODY: send one JSON Patch document; stop the script when the server does not answer 204
patch() {
    printf "%s...\n" "$1"
    RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -X PATCH "${ACCOUNT_URL}" -H "accept: */*" -H "${REFERER_HEADER}" \
      -H "Content-Type: application/json" -d "$2" -w "\n%{http_code}")
    HTTP_CODE="${RESPONSE##*$'\n'}"
    RESPONSE="${RESPONSE%$'\n'*}"
    printf "HTTP %s\n" "${HTTP_CODE}"
    if [ "${HTTP_CODE}" != "204" ]; then
        printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
        exit 1
    fi
}

# The PATCH Method has 3 types of operations: add, remove, and replace.

# OPERATION = ADD
# The add operation is best suited for arrays. You can use it to add a new element to an empty or non-empty array.

# In our first example, lets add an element to the "addressBookSettings.contacts" array.
# The syntax "addressBookSettings.contacts" means that there is a first level property named "addressBookSettings"
# and under that object, there is a property named "contacts".
#
# The addressBookSettings of an account look like this:
# ...
# "addressBookSettings" : {
#     "policy" : "default",
#     "nonAddressBookCollaborationAllowed" : null,
#     "sources" : [ { "name" : "LDAP", "type" : "LDAP", ... }, { "name" : "Local", "type" : "LOCAL", ... } ],
#     "contacts" : [ ]
#   }
# ...
# We will use the replace operation on policy.
# From the schema we can see that the policy can be "default", "custom" or "disabled".
# We will change the policy to "custom".

printf "Getting the account %s and filtering only the addressBookSettings...\n" "${NAME}"
RESPONSE=$(curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${ACCOUNT_URL}" --data-urlencode "type=user" --data-urlencode "fields=addressBookSettings" \
  -H "accept: */*" -H "${REFERER_HEADER}" -w "\n%{http_code}")
HTTP_CODE="${RESPONSE##*$'\n'}"
RESPONSE="${RESPONSE%$'\n'*}"
if [ "${HTTP_CODE}" != "200" ]; then
    printf "Could not read the account %s: HTTP %s\n" "${NAME}" "${HTTP_CODE}"
    printf '%s' "${RESPONSE}" | jq -r '(.validationErrors // [.message // empty])[]' 2>/dev/null || printf '%s\n' "${RESPONSE}"
    exit 1
fi
OLD_POLICY=$(printf '%s' "${RESPONSE}" | jq -r '.addressBookSettings.policy')
OLD_FLAG=$(printf '%s' "${RESPONSE}" | jq -c '.addressBookSettings.nonAddressBookCollaborationAllowed')
SOURCES=$(printf '%s' "${RESPONSE}" | jq '(.addressBookSettings.sources // []) | length')
CONTACTS=$(printf '%s' "${RESPONSE}" | jq '(.addressBookSettings.contacts // []) | length')
printf "The address book settings of %s are now: policy %s, nonAddressBookCollaborationAllowed %s, %s sources, %s contacts.\n" \
  "${NAME}" "${OLD_POLICY}" "${OLD_FLAG}" "${SOURCES}" "${CONTACTS}"
RESTORE=$(jq -cn --arg policy "${OLD_POLICY}" --argjson flag "${OLD_FLAG}" \
  '[{op: "replace", path: "/addressBookSettings/policy", value: $policy}]
   + (if $flag == null then [{op: "remove", path: "/addressBookSettings/nonAddressBookCollaborationAllowed"}]
      else [{op: "replace", path: "/addressBookSettings/nonAddressBookCollaborationAllowed", value: $flag}] end)')
printf "To put the policy and the flag back, PATCH this body: %s\n" "${RESTORE}"

if [ "${SOURCES}" -ge 2 ]; then
    patch "Changing the policy to custom" "$(jq -cn '[{op: "replace", path: "/addressBookSettings/policy", value: "custom"}]')"
else
    printf "Skipping the change to custom: it needs at least two address book sources and this account has %s.\n" "${SOURCES}"
fi

# Now let's repeat the querry, but this time try to modify two parameters at once.
patch "Changing two fields at the same time" "$(jq -cn \
  '[{op: "replace", path: "/addressBookSettings/policy", value: "default"},
    {op: "replace", path: "/addressBookSettings/nonAddressBookCollaborationAllowed", value: "true"}]')"

patch "Removing the addressBookSettings.nonAddressBookCollaborationAllowed" "$(jq -cn \
  '[{op: "remove", path: "/addressBookSettings/nonAddressBookCollaborationAllowed"}]')"

printf "Checking the result...\n"
curl -s -k -u "${ST_USER}:${ST_PASSWORD}" -G -X GET "${ACCOUNT_URL}" --data-urlencode "type=user" \
  --data-urlencode "fields=addressBookSettings.nonAddressBookCollaborationAllowed" -H "accept: */*" -H "${REFERER_HEADER}"
printf "\n"

# "-" appends to the end of the array, whether it is empty or already has
# entries - a numeric index like "1" only works if the array already has an
# element at index 0, confirmed against a real server: it 400s with "Array
# index 1 out of bounds" on a freshly created account with no contacts yet.
patch "Adding a new contact" "$(jq -cn \
  '[{op: "add", path: "/addressBookSettings/contacts/-", value: {fullName: "Jane Doe", primaryEmail: "jane.doe@abc.com"}}]')"
printf "To take the contact out again, PATCH this body: %s\n" \
  "$(jq -cn --argjson index "${CONTACTS}" '[{op: "remove", path: ("/addressBookSettings/contacts/" + ($index | tostring))}]')"
