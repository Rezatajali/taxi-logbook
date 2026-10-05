#!/usr/bin/env bash
set -euo pipefail
# Create Flutter's SDK-matched platform shells without replacing app source.
project_root="$(cd "$(dirname "$0")/.." && pwd)"
scaffold_dir="$(mktemp -d)"
trap 'rm -rf "$scaffold_dir"' EXIT
flutter create --platforms=android,web --org de.tajalli --project-name taxi_logbook "$scaffold_dir"
for platform in android web; do
  if [ ! -d "$project_root/$platform" ]; then
    cp -R "$scaffold_dir/$platform" "$project_root/$platform"
  fi
done
cd "$project_root"
flutter pub get
