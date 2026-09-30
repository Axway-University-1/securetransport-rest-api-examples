#!/bin/bash
# ==============================================================================
# Fake configuration for the offline tests.
#
# These values are deliberately not real and point at nothing. The tests use
# them to confirm that an example substitutes its variables correctly, so they
# have to look like a real configuration.
#
# check_hygiene.sh exempts this one file by name from its credential scan. Do
# not put a real value here. Real values belong in tests/local, which git
# ignores.
# ==============================================================================
export ST_SERVER="st.example.com"
export ST_PORT="8444"
export ST_USER="apiadmin"
export ST_PASSWORD="s3cret"
