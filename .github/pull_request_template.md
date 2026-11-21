## What and why

<!-- What does this change, and why? Link the issue if there is one. -->

## How it was tested

- [ ] `./tests/offline/run_all.sh` passes (no server, no credentials needed)
- [ ] A new or changed script has a test that would have failed before the change (see [CLAUDE.md](../CLAUDE.md))
- [ ] If it talks to the server: checked against a lab server, or with `tests/online/run_online.sh --mock`

## Safety

- [ ] No credentials, tokens, passwords, real hostnames, IP addresses or customer data in code, logs, fixtures or screenshots
- [ ] An example that changes server configuration, or stops or restarts anything, says so in its header and is labelled for test environments only
- [ ] Test data is synthetic (nothing from a real server in `tests/offline/fixtures/`)

## Documentation

- [ ] README or other docs updated where the change needs it
