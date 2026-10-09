#!/usr/bin/env python3
"""
WRITES TO THE SERVER. Runs the real, unmodified 13.Configurations examples 03
to 47 and checks each through the API:

- the read-only ones as they are: options, groups, logging, profiles, the
  database, Sentinel, login settings, maintenance mode, the Admin UI, allowed
  servers, file archiving, cluster information, replication, external stores;
- the ones that change the server, each put back exactly afterwards: two
  options, the file archiving and node threshold settings;
- the database connection test, with a wrong password, so it can only fail;
- the login settings, with a PATCH that sets the value they already have;
- Sentinel, an external store and an S3 storage profile, pointed at stand-ins
  started on this machine (tests/integration/lib/dummy_servers.py): a TCP sink
  the server sends its Sentinel heartbeat to, a fake HashiCorp Vault it logs
  in to and reads a secret from, and a fake S3 bucket it connects to.

Not run: 25 (maintenance mode) and 28 (the keystore password), which change
the whole server; 12 (a logging configuration) runs only to upload the XML
the server already has, unchanged.

The stand-ins need st_callback_host, this machine's address as the server
sees it; without it, those parts are skipped. Needs --write and
st_allow_writes="yes". Everything changed is restored in a finally block.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib"))
import st_client  # noqa: E402
import harness  # noqa: E402
import script_runner as runner  # noqa: E402
import dummy_servers  # noqa: E402

config = st_client.load_config()
harness.require_writes(config, "run the configuration examples for real")

c = st_client.Checker("Configurations, run for real from Admin/API 2.0/bash/13.Configurations")
FOLDER = os.path.join(runner.path("Admin", "API 2.0", "bash"), "13.Configurations")
CALLBACK = config.get("st_callback_host", "")
OPTIONS = ["AddressBook.Limit.DefaultDisplayEntries", "AddressBook.Limit.MaxDisplayEntries"]
# What 19 changes, as the options that hold it: the endpoint itself refuses an
# empty host once one is set, so these put Sentinel back
SENTINEL_OPTIONS = ["AxwaySentinel.RemoteHost.host", "AxwaySentinel.RemoteHost.port", "AxwaySentinel.OverflowFile.path",
                    "AxwaySentinel.Heartbeat.delay"]
REGISTRY = "StorageProfiles.S3.Registry"


script = harness.bind_script(c, FOLDER, timeout=120)


def get(path):
    return admin.get("configurations/" + path).json()


def option_values(name):
    return (get("options/" + name) or {}).get("values")


admin = harness.connect(config, c, mock="the bundled mock does not implement /configurations")
if admin.get("configurations/externalStores", params={"name": "example_vault"}).json().get("result") \
        or "example_s3" in (option_values(REGISTRY) or []):
    c.check("example_vault and example_s3 do not exist yet", False, "remove them first; this check will not touch them")
    admin.logout()
    sys.exit(c.done())

saved = {"options": {n: option_values(n) for n in OPTIONS},
         "sentinel": get("sentinel"),
         "sentinel_options": {n: option_values(n) for n in SENTINEL_OPTIONS},
         "fileArchiving": get("fileArchiving"),
         "nodeThreshold": get("clusterManagement/nodeThreshold"),
         "loginSettings": get("loginSettings"),
         "registry": option_values(REGISTRY)}
written = []
try:
    with runner.real_credentials(runner.path("Admin", "API 2.0", "bash"), config):
        # --- options, groups, logging, profiles
        out = script("03.configurations_options_GET.sh", ["AddressBook.Limit*"])
        c.check("03 lists the options by pattern, with their defaults",
                "  AddressBook.Limit.MaxDisplayEntries = %s (" % saved["options"][OPTIONS[1]][0] in out, out[-300:])
        before = saved["options"]
        script("04.configurations_options_PUT.sh", ["%s=7" % OPTIONS[0], "%s=77" % OPTIONS[1]])
        c.check("04 PUT changed both options", [option_values(n) for n in OPTIONS] == [["7"], ["77"]])
        script("04.configurations_options_PUT.sh", ["%s=%s" % (n, before[n][0] if before[n] else "") for n in OPTIONS])
        c.check("04 PUT put both back", {n: option_values(n) for n in OPTIONS} == before)
        out = script("05.configurations_options_name_HEAD.sh")
        c.check("05 finds AddressBook.Enabled", "exists" in out)
        script("05.configurations_options_name_HEAD.sh", ["No.Such.Option"], expect_rc=1)
        out = script("06.configurations_options_name_GET.sh")
        c.check("06 prints the option's value and default", "  AddressBook.Enabled = " in out and ", default " in out, out[-200:])
        groups = admin.get("configurations/options/groups").json()
        out = script("07.configurations_options_groups_GET.sh")
        c.check("07 lists every group", all("  %s: " % g["name"] in out for g in groups), out[-300:])
        out = script("08.configurations_options_groups_name_GET.sh")
        c.check("08 lists the S3 storage profile group's options", "  %s  " % REGISTRY in out, out[-300:])

        logging = admin.get("configurations/logging").json().get("result", [])
        out = script("09.configurations_logging_GET.sh")
        c.check("09 lists every logging option", all("  %s  %s" % (o["name"], o["profileId"]) in out for o in logging))
        out = script("10.configurations_logging_name_HEAD.sh")
        c.check("10 finds Logging.Admin.config in its profile", "exists in profile" in out, out[-200:])
        out = script("11.configurations_logging_name_GET.sh")
        xml = os.path.join(FOLDER, "Logging.Admin.config.xml")
        if os.path.exists(xml):
            written.append(xml)
            c.check("11 saved the XML", open(xml).read().lstrip().startswith("<"))
            script("12.configurations_logging_name_PUT.sh", [xml])
        else:
            c.check("11 says no XML is set", "none set (HTTP 204)" in out, out[-200:])
            c.info("12 not run: the server has no logging XML to upload back unchanged")
        profiles = admin.get("configurations/profiles").json().get("result", [])
        out = script("13.configurations_profiles_GET.sh")
        c.check("13 lists every profile", all("  %s  %s" % (p["id"], p["name"]) in out for p in profiles))
        out = script("14.configurations_profiles_id_HEAD.sh")
        c.check("14 finds the server's profile", "exists" in out, out[-200:])
        out = script("15.configurations_profiles_id_GET.sh")
        c.check("15 reads the server's profile", "SecureTransport Server Configuration" in out, out[-200:])

        # --- database
        db = get("database")
        out = script("16.configurations_database_GET.sh")
        c.check("16 prints the database type and address", "%s:%s" % (db["host"], db["port"]) in out, out[-200:])
        out = script("17.configurations_database_operations_POST_test.sh", expect_rc=1,
                     env={"DB_PASSWORD": "not-the-password-%s" % os.getpid()})
        c.check("17 tested the connection, which a wrong password fails", "test failed" in out, out[-300:])

        # --- Sentinel, against a TCP sink on this machine
        out = script("18.configurations_sentinel_GET.sh")
        c.check("18 prints whether reporting is on", "  enabled: %s" % str(saved["sentinel"]["enabled"]).lower() in out, out[-200:])
        if not CALLBACK:
            c.info("st_callback_host is not set: Sentinel, the external store and the storage profile are skipped")
        elif saved["sentinel"].get("enabled"):
            c.info("Sentinel reporting is on here already: 19 and 20 are not run, so as not to redirect it")
        else:
            with dummy_servers.TcpSink() as sink:
                script("19.configurations_sentinel_PATCH.sh", [CALLBACK, str(sink.port)])
                c.check("19 PATCH turned reporting on, to the sink", (get("sentinel").get("enabled"), get("sentinel").get("port"))
                        == (True, sink.port))
                c.check("19 the server connected and sent a HEARTBEAT event", sink.wait_for(b'NAME="HEARTBEAT"', 60),
                        sink.received()[:200])
                script("20.configurations_sentinel_PUT.sh")
                c.check("20 PUT turned reporting off again", get("sentinel").get("enabled") is False)

        # --- login settings, maintenance, Admin UI, allowed servers
        out = script("21.configurations_loginSettings_GET.sh")
        c.check("21 prints how end users log in", "  end users: password %s" % saved["loginSettings"]["requirePassword"] in out)
        out = script("23.configurations_loginSettings_PATCH.sh", [saved["loginSettings"]["requirePassword"]], expect_rc=None)
        if "HTTP 204" in out:
            c.check("23 PATCH with the same value changed nothing", get("loginSettings") == saved["loginSettings"])
        else:
            c.check("23 is refused only for the known reason", "adminCertificateFileOrPath" in out, out[-300:])
            c.info("this server's login settings are refused on any change: 22 and 23 cannot be shown working here")
        out = script("24.configurations_maintenance_GET.sh")
        c.check("24 prints the maintenance mode", "  maintenance mode: %s" % get("maintenance")["zduMaintenanceMode"] in out)
        out = script("26.configurations_adminui_GET.sh")
        c.check("26 lists the Admin UI pages", "  Dashboard: " in out, out[-200:])
        allowed = admin.get("configurations/allowedSTServers")
        script("27.configurations_allowedSTServers_GET.sh", expect_rc=0 if allowed.status == 200 else 1)

        # --- file archiving, cluster, node threshold, replication
        fa = saved["fileArchiving"]
        out = script("29.configurations_fileArchiving_GET.sh")
        c.check("29 prints the archiving policy", "  archiving: %s" % fa["globalArchivingPolicy"] in out, out[-200:])
        script("30.configurations_fileArchiving_PUT.sh", [str(fa["maximumFileSizeAllowedToArchive"] + 1)])
        c.check("30 PUT changed the largest file archived",
                get("fileArchiving")["maximumFileSizeAllowedToArchive"] == fa["maximumFileSizeAllowedToArchive"] + 1)
        script("31.configurations_fileArchiving_PATCH.sh", [str((fa["deleteFilesOlderThan"] or 30) + 1)])
        c.check("31 PATCH changed how long archives are kept",
                get("fileArchiving")["deleteFilesOlderThan"] == (fa["deleteFilesOlderThan"] or 30) + 1)
        admin.put("configurations/fileArchiving", fa)
        c.check("the file archiving settings are back as they were", get("fileArchiving") == fa)

        out = script("32.configurations_clusterManagement_GET.sh")
        cluster = get("clusterManagement")
        c.check("32 says whether this is a cluster", ("standalone" in out) == (not cluster.get("isCluster")), out[-200:])
        nt = saved["nodeThreshold"]
        out = script("33.configurations_clusterManagement_nodeThreshold_GET.sh")
        c.check("33 prints the expected nodes", "  expects %s node(s)" % nt["numberOfNodes"] in out, out[-200:])
        script("34.configurations_clusterManagement_nodeThreshold_PUT.sh", [str(nt["numberOfNodes"])])
        c.check("34 PUT turned the email on", get("clusterManagement/nodeThreshold")["sendNotification"] is True)
        script("35.configurations_clusterManagement_nodeThreshold_PATCH.sh", ["false"])
        c.check("35 PATCH turned it off", get("clusterManagement/nodeThreshold")["sendNotification"] is False)
        admin.put("configurations/clusterManagement/nodeThreshold", nt)
        c.check("the node threshold is back as it was", get("clusterManagement/nodeThreshold") == nt)
        out = script("36.configurations_replication_GET.sh")
        c.check("36 prints whether replication is on", "  replication: %s" % str(get("replication")["enabled"]).lower() in out)

        # --- an external store, against a fake Vault on this machine
        script("37.configurations_externalStores_GET.sh")
        if CALLBACK:
            with dummy_servers.FakeVault() as vault:
                url = "http://%s:%d" % (CALLBACK, vault.port)
                script("38.configurations_externalStores_POST.sh", [url],
                       env={"VAULT_ROLE_ID": "example-role", "VAULT_SECRET_ID": "example-secret"})
                c.check("38 created example_vault", admin.exists("configurations/externalStores/example_vault"))
                out = script("37.configurations_externalStores_GET.sh", ["example_vault"])
                c.check("37 lists it by its exact name", "  example_vault  %s/v1/secret/data" % url in out, out[-200:])
                out = script("39.configurations_externalStores_name_GET.sh")
                c.check("39 reads it", "  example_vault: GET %s/v1/secret/data" % url in out, out[-200:])
                script("40.configurations_externalStores_name_PUT.sh", ["11"])
                c.check("40 PUT changed readTimeout", get("externalStores/example_vault")["readTimeout"] == 11)
                script("41.configurations_externalStores_name_PATCH.sh", ["120"])
                c.check("41 PATCH changed cacheTimeout", get("externalStores/example_vault")["cacheTimeout"] == 120)
                out = script("42.configurations_externalStores_name_operations_POST_test.sh", ["example/db"])
                c.check("42 the server logged in and fetched the secret, masked",
                        "fetch: Success" in out and "  the secret holds: password, username" in out, out[-300:])
                c.check("42 the fake Vault saw the AppRole login and the read, with the token",
                        any(r["path"] == "/v1/auth/approle/login" and b'"example-role"' in r["body"] for r in vault.requests)
                        and any(r["path"] == "/v1/secret/data/example/db"
                                and r["headers"].get("X-Vault-Token") == dummy_servers.FakeVault.TOKEN for r in vault.requests))
                out = script("42.configurations_externalStores_name_operations_POST_test.sh", ["example/missing"], expect_rc=1)
                c.check("42 a missing secret is reported, fetch Failure", "fetch: Failure" in out, out[-200:])
                out = script("43.configurations_externalStores_name_operations_POST_clearCache.sh", ["example/db"])
                c.check("43 cleared the cache", "Cache was cleared successfully" in out, out[-200:])
                script("44.configurations_externalStores_name_DELETE.sh")
                c.check("44 deleted example_vault", not admin.exists("configurations/externalStores/example_vault"))

            # --- an S3 storage profile, against a fake S3 on this machine
            with dummy_servers.FakeS3() as s3:
                endpoint = "http://%s:%d" % (CALLBACK, s3.port)
                script("45.configurations_storageProfiles_options_PUT_register.sh", ["example-bucket", "us-east-1", endpoint],
                       env={"S3_ACCESS_KEY": "example-access-key", "S3_SECRET_KEY": "example-secret-key"})
                c.check("45 registered example_s3, keeping the other profiles",
                        option_values(REGISTRY) == sorted(set([v for v in (saved["registry"] or []) if v] + ["example_s3"])))
                c.check("45 set its bucket and endpoint",
                        (option_values(REGISTRY + ".example_s3.Bucket"), option_values(REGISTRY + ".example_s3.CustomEndpointUrl"))
                        == (["example-bucket"], [endpoint]))
                seen = len(s3.requests)
                script("46.configurations_storageProfiles_name_operations_POST_test.sh")
                c.check("46 the server reached the bucket", any(r["method"] == "HEAD" and r["path"] == "/example-bucket"
                                                                for r in s3.requests[seen:]))
                script("46.configurations_storageProfiles_name_operations_POST_test.sh", ["no_such_profile"], expect_rc=1)
                script("47.configurations_storageProfiles_options_PUT_unregister.sh")
                c.check("47 removed example_s3 and its options", "example_s3" not in (option_values(REGISTRY) or [])
                        and not admin.get("configurations/options", params={"name": REGISTRY + ".example_s3.*"}).json()["result"])
finally:
    if admin.exists("configurations/externalStores/example_vault"):
        admin.delete("configurations/externalStores/example_vault")
    if "example_s3" in (option_values(REGISTRY) or []):
        admin.put("configurations/options", [{"name": REGISTRY, "values": saved["registry"] or [""]}])
    admin.put("configurations/options", [{"name": n, "values": v or [""]} for n, v in saved["options"].items()])
    if get("sentinel") != saved["sentinel"]:
        # The endpoint refuses an empty host once one is set: off first, then the options
        admin.patch("configurations/sentinel", [{"op": "replace", "path": "/enabled", "value": saved["sentinel"]["enabled"]},
                                                {"op": "replace", "path": "/heartbeatEnabled", "value": saved["sentinel"]["heartbeatEnabled"]}])
        admin.put("configurations/options", [{"name": n, "values": v or [""]} for n, v in saved["sentinel_options"].items()])
    if get("fileArchiving") != saved["fileArchiving"]:
        admin.put("configurations/fileArchiving", saved["fileArchiving"])
    if get("clusterManagement/nodeThreshold") != saved["nodeThreshold"]:
        admin.put("configurations/clusterManagement/nodeThreshold", saved["nodeThreshold"])
    for path in written:
        os.remove(path)
    now = {"options": {n: option_values(n) for n in OPTIONS}, "sentinel": get("sentinel"),
           "fileArchiving": get("fileArchiving"), "nodeThreshold": get("clusterManagement/nodeThreshold"),
           "loginSettings": get("loginSettings"), "registry": option_values(REGISTRY)}
    for key, value in now.items():
        c.check("%s is exactly as it was" % key, value == saved[key], json.dumps(value)[:300])
    c.check("no external store or storage profile is left", not admin.exists("configurations/externalStores/example_vault")
            and "example_s3" not in (option_values(REGISTRY) or []))
    admin.logout()

sys.exit(c.done())
