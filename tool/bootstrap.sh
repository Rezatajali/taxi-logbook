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
# Use the product name in installed Android apps and browser tabs.
python3 - <<'PY'
import json
from pathlib import Path
manifest = Path('android/app/src/main/AndroidManifest.xml')
manifest.write_text(manifest.read_text().replace('android:label="taxi_logbook"', 'android:label="Taxi Logbuch"'))
index = Path('web/index.html')
index.write_text(index.read_text().replace('<title>taxi_logbook</title>', '<title>Taxi Logbuch</title>')
    .replace('A new Flutter project.', 'Fahrten und Umsätze einfach erfassen.'))
web_manifest = Path('web/manifest.json')
data = json.loads(web_manifest.read_text())
data.update(name='Taxi Logbuch', short_name='Logbuch', description='Dein Fahrten- und Umsatzbuch',
    background_color='#F5F6F2', theme_color='#153E35')
web_manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2))
PY
flutter pub get
