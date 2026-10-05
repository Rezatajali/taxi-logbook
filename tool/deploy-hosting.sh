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
npx --yes firebase-tools login --no-localhost
npx --yes firebase-tools deploy --only hosting --project taxi-logbook-d1104
