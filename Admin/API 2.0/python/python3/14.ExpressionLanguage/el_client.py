#!/usr/bin/env python3
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
# Minimal shared HTTP helper for the Expression Language exercises in this
# folder. This is not a standalone example itself - every other script here
# imports it, so each one can stay focused on the one EL expression it
# demonstrates rather than repeat the same login/logout boilerplate the rest
# of this python3/ folder's examples already show many times over
# (stConfigScan.py, stGetAccountsAfterDate.py, stBuildTestAccounts.py, ...).
#
# Needs the requests library, same as every other script in python3/:
#     python3 -m pip install requests
#
# Reads Admin/API 2.0/python/config, two directories up from this file - one
# level further than the other python3/ examples, since this folder is nested
# one level deeper than they are. The same optional keys apply as everywhere:
# st_ca_bundle (a file) or st_verify=yes turn on the check of the server's
# certificate.
#
# What every script here relies on, so it is said once:
# - Every call that cannot complete (no connection, a timeout, anything the
#   requests library raises) ends the script with exit code 1 and a message.
#   A call that completes with a bad status is the script's to look at: see
#   ELClient.expect().
# - The csrfToken of the login is sent on every later call, as the server
#   expects from the 20230525 release on.
# - The scripts clean up only what they created: ELClient.finish() deletes the
#   ids it is given, never an object found by its name.
#
import base64
import os
import sys

import requests
from requests.packages.urllib3.exceptions import InsecureRequestWarning


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
        sys.exit(1)

    if not all(config.get(k) for k in ("st_server", "st_port", "st_user", "st_password")):
        print("The configuration file must set st_server, st_port, st_user and st_password.")
        sys.exit(1)
    return config


def created_id(response):
    """The id of a new object: the last part of the Location header of the 201, or None."""
    location = response.headers.get("Location") or ""
    return location.rstrip("/").rsplit("/", 1)[-1] or None


class ELClient:
    """A tiny logged in session - just enough for these exercises."""

    def __init__(self, config, referer="THIS_IS_A_RANDOM_TEXT"):
        self.base = "https://%s:%s/api/v2.0/" % (config["st_server"], config["st_port"])
        self.referer = referer
        # Verify the server's certificate when st_ca_bundle (a file) or st_verify=yes is set
        self.verify = config.get("st_ca_bundle", "") or config.get("st_verify", "no").lower() in ("yes", "true", "1")
        if not self.verify:
            requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
        self.failed = False
        self.session = requests.Session()
        auth = base64.b64encode(
            ("%s:%s" % (config["st_user"], config["st_password"])).encode()).decode()
        response = self._send("POST", "myself", headers={"Referer": referer, "Accept": "application/json",
                                                         "Authorization": "Basic " + auth})
        if response.status_code != 200:
            print("Cannot login:", response.status_code, response.text)
            sys.exit(1)
        # Present from the 20230525 release; absent on older servers, which
        # is not an error - later calls simply do not send the header.
        self.csrf = response.headers.get("csrfToken")
        self.logged_in = True

    def _headers(self, extra=None):
        headers = {"Referer": self.referer, "Accept": "application/json"}
        if self.csrf:
            headers["csrfToken"] = self.csrf
        if extra:
            headers.update(extra)
        return headers

    def _send(self, method, path, fatal=True, **kwargs):
        """One request. A call that cannot complete is exit 1, or None when fatal is False."""
        try:
            return getattr(self.session, method.lower())(self.base + path, verify=self.verify, timeout=30, **kwargs)
        except requests.exceptions.RequestException as e:
            print("The %s %s failed: %s %s" % (method, path, type(e).__name__, e))
            if fatal:
                sys.exit(1)
            self.failed = True
            return None

    def expect(self, response, statuses, what):
        """Exit 1 unless the status of the response is one of statuses."""
        if response.status_code not in statuses:
            print("%s answered %s: %s" % (what, response.status_code, response.text[:300]))
            sys.exit(1)

    def get(self, path, params=None):
        return self._send("GET", path, headers=self._headers(), params=params)

    def post(self, path, body):
        return self._send("POST", path, headers=self._headers({"Content-Type": "application/json"}), json=body)

    def patch(self, path, body):
        return self._send("PATCH", path, headers=self._headers({"Content-Type": "application/json"}), json=body)

    def delete(self, path, fatal=True):
        return self._send("DELETE", path, fatal=fatal, headers=self._headers())

    def logout(self):
        """Log out. This is housekeeping, so a failure is a warning and never an exception."""
        if not getattr(self, "logged_in", False):
            return
        response = self._send("DELETE", "myself", fatal=False, headers=self._headers())
        if response is None or response.status_code != 200:
            print("The logout did not work (%s)" % (response.status_code if response is not None else "no answer"))
            self.failed = True
        self.logged_in = False

    def track(self, created, collection, response, name, key=None):
        """
        Remember an object a 201 just created, so finish() can delete it: by key when the
        path takes the name, else by the id in the Location header. Without an id the
        object is left alone and the run is marked failed, rather than looked up by name.
        """
        ident = key or created_id(response)
        if not ident:
            print("%s was created but the answer has no Location: remove it by hand" % name)
            self.failed = True
            return
        created.append((collection, ident, name))

    def finish(self, created=()):
        """
        The end of every script, in its `finally`: delete what it created (a list of
        (collection, id, name), newest first), log out, and exit 1 if any of that failed.
        Only the ids given are deleted. An object that was there before the script ran,
        even one with the same name, is never touched.
        """
        for collection, ident, name in reversed(list(created)):
            response = self.delete("%s/%s" % (collection, ident), fatal=False)
            if response is not None and response.status_code == 204:
                print("deleted %s (%s)" % (name, ident))
            else:
                print("COULD NOT DELETE %s/%s (%s): remove it by hand" %
                      (collection, ident, response.status_code if response is not None else "no answer"))
                self.failed = True
        self.logout()
        if self.failed:
            sys.exit(1)
