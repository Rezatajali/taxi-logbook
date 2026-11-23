#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f build/web/index.html ]; then
  echo "Missing web build. Extract the Hosting package or build Web first." >&2
  exit 1
fi
if ! command -v npx >/dev/null 2>&1; then
  echo "Install Node.js LTS first: https://nodejs.org/" >&2
  exit 1
fi
# Pin the CLI version so a compromised or broken new release is not run automatically.
firebase_tools="firebase-tools@15.34.2"
npx --yes "$firebase_tools" login --no-localhost
npx --yes "$firebase_tools" deploy --only hosting --project taxi-logbook-d1104
