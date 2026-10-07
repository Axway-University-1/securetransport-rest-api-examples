"""
Talk to the lab server from a probe script, and run the real examples on it.
Reads tests/local/integration.conf, like the integration checks.

    import sys; sys.path.insert(0, ".claude/skills/st-api-cover-resource/scripts")
    from lab import admin, show, run
    show("list", admin.get("deniedUsers"))                   # one line: label, HTTP, body
    show("create", admin.post("deniedUsers", {...}), 300)
    run("22.DeniedUsers", [("01.deniedUsers_GET.sh", None),
                           ("02.deniedUsers_POST.sh", ["someone"])])

PROBE WITH THROWAWAY OBJECTS ONLY, named example_* so they are easy to find,
and delete them (or put a setting back exactly) in a finally block.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _repo import BASH, INTEGRATION_LIB  # noqa: E402

sys.path.insert(0, INTEGRATION_LIB)
import st_client  # noqa: E402
import script_runner as runner  # noqa: E402

config = st_client.load_config()
if not config:
    sys.exit("No tests/local/integration.conf: copy tests/integration/integration.conf.example and fill it in.")
admin = st_client.client_from_config(config)
admin.login()


def show(label, response, width=600):
    print("%-48s HTTP %s %s" % (label, response.status, response.text.replace("\n", " ")[:width]))
    return response


def run(folder, steps, env=None, tail=1500):
    """Run bash examples on the lab, with the real credentials put in place and
    taken away again. steps: [(script name, [args] or None)]."""
    if env:
        os.environ.update(env)
    with runner.real_credentials(BASH, config):
        for name, args in steps:
            result = runner.run(os.path.join(BASH, folder, name), args, timeout=90)
            print("=== %s %s -> rc %s" % (name, " ".join(args or []), result.returncode))
            print((result.stdout + result.stderr)[-tail:])
