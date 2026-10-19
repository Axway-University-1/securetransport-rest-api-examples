"""
Synthetic servers for the end to end runs of the python examples (run_example.py).
Nothing here comes from a real server.
"""
import json
import os

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "fixtures")


def fixture(name):
    with open(os.path.join(FIXTURES, name)) as fh:
        return json.load(fh)


def world(**collections):
    return {"collections": collections}


USERS = [
    {"id": "a1", "name": "ZZ0", "type": "user", "accountCreationDate": 1700000000000},
    {"id": "a2", "name": "ZZ1", "type": "user", "accountCreationDate": 1800000000000},
    {"id": "a3", "name": "john", "type": "user"},
    {"id": "a4", "name": "myZZ", "type": "user"},
    {"id": "a5", "name": "zz9", "type": "user"},
    {"id": "a6", "name": "ZZtemplate", "type": "template", "enrolledWithExternalPass": True},
    {"id": "a7", "name": "ZZservice", "type": "service"},
]
MASTER_KEX = ("diffie-hellman-group14-sha256,diffie-hellman-group-exchange-sha256,curve25519-sha256@libssh.org,"
              "diffie-hellman-group15-sha512,diffie-hellman-group17-sha512,diffie-hellman-group16-sha512,"
              "diffie-hellman-group18-sha512")
SITES = [
    {"id": "s1", "name": "PartnerOne", "protocol": "ssh", "account": "john", "keyExchangeAlgorithms": "old-kex"},
    {"id": "s2", "name": "PartnerTwo", "protocol": "ssh", "account": "jane", "keyExchangeAlgorithms": MASTER_KEX},
    {"id": "s3", "name": "PartnerThree", "protocol": "ssh", "account": "jane", "keyExchangeAlgorithms": "other-kex"},
    {"id": "s4", "name": "WebPartner", "protocol": "http", "account": "jane"},
]
SUBSCRIPTIONS = [dict(s, postProcessingActions={"ppaOnSuccessInDoDelete": False}) for s in fixture("subscriptions.json")]
CERTIFICATES = [{"id": "c1", "name": "cert one", "usage": "private", "account": "john", "endDate": "2020-01-01T00:00:00Z"},
                {"id": "c2", "name": "cert two", "usage": "partner", "endDate": "2999-01-01T00:00:00Z"},
                # two that expire at the same moment: sorting the pairs must not compare the certificates
                {"id": "c3", "name": "cert three", "usage": "trusted", "endDate": "2020-01-01T00:00:00Z"},
                {"id": "c4", "name": "cert four", "usage": "trusted", "endDate": "2999-01-01T00:00:00Z"}]
OPTIONS = [{"name": "A.One", "values": ["1"]}, {"name": "B.Two", "values": ["2"]}, {"name": "D.Four", "values": ["4"]}]
