#!/usr/bin/env python3
"""
The bundled mock of SecureTransport (tests/integration/mock/mock_st.py) has to
behave like the real server for what the accounts examples do, or the checks
that run them under --mock fail for reasons that are the mock's own:

  - a JSON Patch with a nested path ("/addressBookSettings/contacts/-"), which
    05.Accounts/06 sends and the mock first read as a top level field named
    "addressBookSettings/contacts/-"
  - a type specific field (addressBookSettings), which the whole object carries
    without any type=, and which only fields= needs the type for

Runs offline. Exit code 0 means clean.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
spec = importlib.util.spec_from_file_location("mock_st", os.path.join(REPO, "tests", "integration", "mock", "mock_st.py"))
mock_st = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mock_st)

failed = 0


def check(label, ok, got=None):
    global failed
    print(("  PASS  " if ok else "  FAIL  ") + label + ("" if ok or got is None else "  got: %r" % (got,)))
    failed += 0 if ok else 1


def fresh():
    return {"name": "a", "type": "user", "notes": None,
            "addressBookSettings": {"policy": "default", "nonAddressBookCollaborationAllowed": None,
                                    "sources": [], "contacts": [{"fullName": "one"}]}}


print("=== JSON Patch on a nested document ===")
doc = fresh()
check("replace of a nested field", mock_st.apply_patch_operation(doc, "replace", "/addressBookSettings/policy", "custom") is None
      and doc["addressBookSettings"]["policy"] == "custom", doc)
doc = fresh()
check("add with - appends to a list that already has an element",
      mock_st.apply_patch_operation(doc, "add", "/addressBookSettings/contacts/-", {"fullName": "two"}) is None
      and [c["fullName"] for c in doc["addressBookSettings"]["contacts"]] == ["one", "two"], doc)
doc = fresh()
doc["addressBookSettings"]["contacts"] = []
check("add with - appends to an empty list too",
      mock_st.apply_patch_operation(doc, "add", "/addressBookSettings/contacts/-", {"fullName": "x"}) is None
      and len(doc["addressBookSettings"]["contacts"]) == 1, doc)
doc = fresh()
doc["addressBookSettings"]["contacts"] = []
check("add at index 1 of an empty list is refused, as on the real server",
      "out of bounds" in (mock_st.apply_patch_operation(doc, "add", "/addressBookSettings/contacts/1", {}) or ""))
doc = fresh()
check("remove takes a nested field out", mock_st.apply_patch_operation(doc, "remove", "/addressBookSettings/nonAddressBookCollaborationAllowed", None) is None
      and doc["addressBookSettings"].get("nonAddressBookCollaborationAllowed") is None, doc)
doc = fresh()
check("remove of a list element by its index", mock_st.apply_patch_operation(doc, "remove", "/addressBookSettings/contacts/0", None) is None
      and doc["addressBookSettings"]["contacts"] == [], doc)
doc = fresh()
check("replace of a field that is not there is refused",
      "missing field" in (mock_st.apply_patch_operation(doc, "replace", "/addressBookSettings/nope", 1) or ""))
check("a path through a field that is not there is refused",
      'Missing field "nope"' == mock_st.apply_patch_operation(doc, "add", "/nope/x", 1))
doc = fresh()
check("a top level field still works", mock_st.apply_patch_operation(doc, "add", "/notes", "hi") is None and doc["notes"] == "hi", doc)

print()
print("=== the type specific field ===")
acc = fresh()
check("the whole object has addressBookSettings without type=", "addressBookSettings" in mock_st.filter_account_fields(dict(acc), {}))
check("fields=addressBookSettings without type= leaves it out", "addressBookSettings" not in mock_st.filter_account_fields(dict(acc), {"fields": "addressBookSettings"}))
check("fields=addressBookSettings with type=user has it",
      "addressBookSettings" in mock_st.filter_account_fields(dict(acc), {"fields": "addressBookSettings", "type": "user"}))
check("fields=type answers the type", mock_st.filter_account_fields(dict(acc), {"fields": "type"}) == {"type": "user"})

print()
print("=== the query string ===")


class FakeRequest:
    path = "/api/v2.0/accounts/a%20b?type=template&fields=type%2CtemplateClass&x=1+2"


path, params = mock_st.Handler._split(FakeRequest())
check("a comma that curl -G or the harness encoded as %2C is read as a comma (fields=type,templateClass)",
      params.get("fields") == "type,templateClass" and params.get("type") == "template", params)
check("a + in a value is a space, as in a query string", params.get("x") == "1 2", params)

print()
if failed:
    print("test_mock_st: FAIL (%d)" % failed)
    sys.exit(1)
print("test_mock_st: PASS")
