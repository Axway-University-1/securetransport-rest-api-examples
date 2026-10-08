#!/usr/bin/env python3
"""
Real logins over the three protocols a check can use on the lab, shared by the checks that must do the same
thing for each: SFTP and HTTP (the EndUser API) are the CORE protocols, FTP is the legacy, additional one.

  - SFTP: the system `sftp` client, kept open by its standard input, the password given by SSH_ASKPASS
    (no terminal, no extra module; the password goes in an environment variable; works on macOS and Linux). Logins only: no file is sent.
  - HTTP: an EndUser API login (POST /myself with Basic authentication).
  - FTP:  ftplib.

`Logins(host, ssh_port, enduser_port, ftp_port, password)` has:
  try_login(proto, account, password=None) -> "ok" or "refused (...)" or "error (...)"; the login is closed at once
  open_login(proto, account)               -> a Holder whose alive() / close() work on a login kept open
  cleanup()                                -> ends every sftp process this object started, removes its temp folder
"""
import ftplib
import os
import shutil
import stat
import subprocess
import tempfile

import st_client

PROTOCOLS = ("SFTP", "HTTP", "FTP")        # FTP is the legacy one
SESSION_PROTOCOL = {"SFTP": "SSH", "HTTP": "HTTP", "FTP": "FTP"}


class Holder:
    """One open login: alive() says whether the client is still connected, close() ends it."""

    def __init__(self, alive, close):
        self.alive, self.close = alive, close


class Logins:
    def __init__(self, host, ssh_port, enduser_port, ftp_port, password):
        self.host, self.ssh_port, self.enduser_port, self.ftp_port, self.password = host, ssh_port, enduser_port, ftp_port, password
        self.work = tempfile.mkdtemp(prefix="protocol_logins_")
        self.procs = []

    def _askpass(self):
        """A script that prints the password from the environment: no password text is ever put into shell code."""
        path = os.path.join(self.work, "askpass.sh")
        if not os.path.exists(path):
            with open(path, "w") as f:
                f.write("#!/bin/sh\nprintf '%s\\n' \"$PROTOCOL_LOGINS_PASSWORD\"\n")
            os.chmod(path, stat.S_IRWXU)
        return path

    def _env(self, password):
        return dict(os.environ, SSH_ASKPASS=self._askpass(), SSH_ASKPASS_REQUIRE="force", DISPLAY="x", PROTOCOL_LOGINS_PASSWORD=password)

    def _sftp(self, account, password):
        proc = subprocess.Popen(["sftp", "-P", str(self.ssh_port), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
                                 "-o", "PreferredAuthentications=password", "-o", "NumberOfPasswordPrompts=1", "-o", "ConnectTimeout=15",
                                 "%s@%s" % (account, self.host)],
                                env=self._env(password),
                                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        self.procs.append(proc)
        return proc

    def open_login(self, proto, account, password=None):
        """Log in and keep the connection open. Raises st_client.STError when the login is refused."""
        password = password or self.password
        if proto == "FTP":
            client = ftplib.FTP()
            client.connect(self.host, self.ftp_port, timeout=30)
            client.login(account, password)

            def alive():
                try:
                    client.voidcmd("NOOP")
                    return True
                except (OSError, EOFError, ftplib.Error):
                    return False
            return Holder(alive, client.close)
        if proto == "HTTP":
            client = st_client.EndUserClient(self.host, self.enduser_port, account, password)
            login = client._request("POST", "myself", headers={"Authorization": "Basic " + client._auth})
            if login.status != 200:
                raise st_client.STError("EndUser login of %s answered %s" % (account, login.status))
            return Holder(lambda: client._request("GET", "myself").status == 200, lambda: client.logout())
        proc = self._sftp(account, password)

        def close():
            try:
                proc.stdin.close()
            except OSError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.terminate()
        return Holder(lambda: proc.poll() is None, close)

    def try_login(self, proto, account, password=None):
        """'ok' when the login was accepted, 'refused (...)' when it was not, 'error (...)' when it could not be tried.
        The login is closed again. An sftp login is accepted when `pwd` is answered."""
        password = password or self.password
        try:
            if proto == "FTP":
                client = ftplib.FTP()
                client.connect(self.host, self.ftp_port, timeout=15)
                client.login(account, password)
                client.quit()
                return "ok"
            if proto == "HTTP":
                client = st_client.EndUserClient(self.host, self.enduser_port, account, password)
                response = client._request("POST", "myself", headers={"Authorization": "Basic " + client._auth})
                if response.status == 200:
                    client.logout()
                    return "ok"
                return "refused (HTTP %s)" % response.status
            # `pwd` answers only on a logged in session: the login is proved by the server's answer, not by a timer
            proc = subprocess.Popen(["sftp", "-P", str(self.ssh_port), "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
                                     "-o", "PreferredAuthentications=password", "-o", "NumberOfPasswordPrompts=1", "-o", "ConnectTimeout=15",
                                     "%s@%s" % (account, self.host)],
                                    env=self._env(password),
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
            self.procs.append(proc)
            try:
                out, err = proc.communicate(b"pwd\nbye\n", timeout=30)
            except subprocess.TimeoutExpired:
                proc.kill()
                return "error (sftp timed out)"
            if b"Remote working directory" in out:
                return "ok"
            # only the server saying no is a refusal; a port nobody answers on, a timeout, a name that does not resolve is an error
            if b"permission denied" in err.lower() or b"authentication failed" in err.lower():
                return "refused (sftp exited %s)" % proc.returncode
            return "error (sftp exited %s: %s)" % (proc.returncode, err.decode("utf-8", "replace").strip()[-60:] or "no message")
        except ftplib.error_perm as e:
            return "refused (%s)" % str(e)[:40]
        except (OSError, EOFError, ftplib.Error, st_client.STError) as e:
            return "error (%s)" % type(e).__name__

    def cleanup(self):
        for proc in self.procs:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
        shutil.rmtree(self.work, ignore_errors=True)
