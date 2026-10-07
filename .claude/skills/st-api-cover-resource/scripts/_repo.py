"""Paths shared by the authoring tools. Nothing here talks to a server."""
import os

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SPEC_DIR = os.path.join(REPO, "tests", "local", "admin20-spec")
BASH = os.path.join(REPO, "Admin", "API 2.0", "bash")
BAT = os.path.join(REPO, "Admin", "API 2.0", "bat")
INTEGRATION_LIB = os.path.join(REPO, "tests", "integration", "lib")
