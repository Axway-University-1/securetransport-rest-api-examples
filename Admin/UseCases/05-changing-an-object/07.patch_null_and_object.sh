#!/bin/bash
# ==============================================================================
# Script Name: 07.patch_null_and_object.sh
# Author: Plamen Milenkov
# Created: 2026-10-30
# Location: Sofia
# ==============================================================================
# Description:
# Changing an object, step 7: a null, and a nested OBJECT. A null in the answer is a field with no value, and PATCH can write one (replace with null) when the field may be empty. A nested object (contact,
# bandwidthLimits) is replaced whole by a replace on its path, and what the new object leaves out is reset. Each case shows the body sent, the answer and the field before and after.
#
# Usage:
# ./07.patch_null_and_object.sh [NAME]
#
#   NAME  the account (and NAME_route, the route) to change; it must start with example_ (default example_chg)
#
# Risk: write
#
# Notes:
# - Written for this use case, from the Admin API reference and what the lab answers. Every call is a PATCH with a list of operations.
# - Replace with null clears a field that may be empty (contact.email). A field that must have a value refuses it (disabled: 400).
# - Replace on the path of an object takes the whole new object: a field it leaves out is reset to null. Replace on the path of a field inside it changes that field only.
# - `remove` on an object does not remove it from the answer: its fields become null and the object stays. Replace of the object with null is refused, with a message about the server's code, not about your value.
# - Exit 1 when a case does not come out as the README documents (the line NOT AS DOCUMENTED says which).
# ==============================================================================

source "$(dirname "$(realpath "$0")")/lib.sh"
USAGE="Usage: ./07.patch_null_and_object.sh [NAME]"
if [ "$#" -gt 1 ]; then printf "%s parameters were given, and at most 1 is taken: NAME.\n%s\n" "$#" "${USAGE}"; exit 2; fi
NAME="${1:-${DEFAULT_NAME}}"
uc_check_name "${NAME}" "${USAGE}"
st_session
uc_init "${NAME}"
uc_need account

uc_case "replace with null clears a field that may be empty" "${ACCOUNT_URL}" '.contact.email' 204 'null' \
    '[{"op":"replace","path":"/contact/email","value":null}]'
uc_case "null on a field that must have a value is refused" "${ACCOUNT_URL}" '.disabled' 400 'false' \
    '[{"op":"replace","path":"/disabled","value":null}]'
uc_case "replace a whole object: every field of it is in the value" "${ACCOUNT_URL}" '.bandwidthLimits' 204 '{"policy":"custom","inboundLimit":100,"outboundLimit":200}' \
    '[{"op":"replace","path":"/bandwidthLimits","value":{"policy":"custom","inboundLimit":100,"outboundLimit":200}}]'
uc_case "replace a whole object with a fragment: what is left out is reset to null" "${ACCOUNT_URL}" '.bandwidthLimits' 204 '{"policy":"custom","inboundLimit":100,"outboundLimit":null}' \
    '[{"op":"replace","path":"/bandwidthLimits","value":{"policy":"custom","inboundLimit":100}}]'
uc_case "replace one field inside it: only that field changes" "${ACCOUNT_URL}" '.bandwidthLimits' 204 '{"policy":"custom","inboundLimit":100,"outboundLimit":300}' \
    '[{"op":"replace","path":"/bandwidthLimits/outboundLimit","value":300}]'
uc_case "replace the object contact" "${ACCOUNT_URL}" '.contact' 204 '{"email":"a@example.com","phone":"123"}' \
    '[{"op":"replace","path":"/contact","value":{"email":"a@example.com","phone":"123"}}]'
uc_case "remove an object: it stays in the answer with every field null" "${ACCOUNT_URL}" '.contact' 204 '{"email":null,"phone":null}' \
    '[{"op":"remove","path":"/contact"}]'
uc_case "replace an object with null is refused" "${ACCOUNT_URL}" '.contact' 400 '{"email":null,"phone":null}' \
    '[{"op":"replace","path":"/contact","value":null}]'
uc_done
