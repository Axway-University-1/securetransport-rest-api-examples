#!/usr/bin/env python3
"""
Minimal shared HTTP helper for the Expression Language exercises in this
folder. This is not a standalone example itself - every other script here
imports it, so each one can stay focused on the one EL expression it
demonstrates rather than repeat the same login/logout boilerplate the rest
of this python3/ folder's examples already show many times over
(stConfigScan.py, stGetAccountsAfterDate.py, stBuildTestAccounts.py, ...).

Needs the requests library, same as every other script in python3/:
    python3 -m pip install requests

Reads Admin/API 2.0/python/config, two directories up from this file - one
level further than the other python3/ examples, since this folder is nested
one level deeper than they are.
"""
import base64
import os
import sys

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning

requests.packages.urllib3.disable_warnings(InsecureRequestWarning)


def load_config():
    config_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "config")
    config = {}
    try:
        with open(config_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                config[key.strip()] = value.strip().strip('"')
    except IOError:
        print("I cannot find the configuration file: " + config_file)
        print("Copy config.example to config and set the values for your environment.")
        sys.exit(0)

    if not all(config.get(k) for k in ("st_server", "st_port", "st_user", "st_password")):
        print("The configuration file must set st_server, st_port, st_user and st_password.")
        sys.exit(0)
    return config


class ELClient:
    """A tiny logged in session - just enough for these exercises."""

    def __init__(self, config, referer="THIS_IS_A_RANDOM_TEXT"):
        self.base = "https://%s:%s/api/v2.0/" % (config["st_server"], config["st_port"])
        self.referer = referer
        self.session = requests.Session()
        auth = base64.b64encode(
            ("%s:%s" % (config["st_user"], config["st_password"])).encode()).decode()
        response = self.session.post(
            self.base + "myself",
            headers={"Referer": referer, "Accept": "application/json",
                     "Authorization": "Basic " + auth},
            verify=False, timeout=30)
        if response.status_code != 200:
            print("Cannot login:", response.status_code, response.text)
            sys.exit(1)
        # Present from the 20230525 release; absent on older servers, which
        # is not an error - later calls simply do not send the header.
        self.csrf = response.headers.get("csrfToken")

    def _headers(self, extra=None):
        headers = {"Referer": self.referer, "Accept": "application/json"}
        if self.csrf:
            headers["csrfToken"] = self.csrf
        if extra:
            headers.update(extra)
        return headers

    def get(self, path, params=None):
        return self.session.get(self.base + path, headers=self._headers(),
                                params=params, verify=False, timeout=30)

    def post(self, path, body):
        return self.session.post(self.base + path,
                                 headers=self._headers({"Content-Type": "application/json"}),
                                 json=body, verify=False, timeout=30)

    def patch(self, path, body):
        return self.session.patch(self.base + path,
                                  headers=self._headers({"Content-Type": "application/json"}),
                                  json=body, verify=False, timeout=30)

    def delete(self, path):
        return self.session.delete(self.base + path, headers=self._headers(),
                                   verify=False, timeout=30)

    def logout(self):
        self.session.delete(self.base + "myself", headers=self._headers(),
                            verify=False, timeout=30)
