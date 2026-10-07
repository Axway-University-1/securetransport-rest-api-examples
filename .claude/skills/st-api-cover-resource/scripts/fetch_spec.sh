#!/bin/bash
# Downloads the Admin API 2.0 reference (swagger.yaml and every schema file it
# references) into tests/local/admin20-spec/, which git ignores, then indexes its
# operations by tag into ops_by_tag.json. Safe to run again.
set -eu
DIR="$(cd "$(dirname "$0")/../../../.." && pwd)/tests/local/admin20-spec"
BASE="https://apidocs.axway.com/swagger-ui-st/admin-20"
mkdir -p "${DIR}"
cd "${DIR}"
curl -sfL --max-time 60 -o swagger.yaml "${BASE}/swagger.yaml"
for f in $(grep -ohE "'[A-Za-z0-9_]+\.yaml" swagger.yaml | tr -d "'" | sort -u); do
    curl -sfL --max-time 60 -o "${f}" "${BASE}/${f}"
done
python3 "$(dirname "$0")/endpoint.py" --index
printf "Spec in %s: %s files\n" "${DIR}" "$(ls "${DIR}" | wc -l | tr -d ' ')"
