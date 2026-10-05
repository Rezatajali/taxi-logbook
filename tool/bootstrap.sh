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
import re
from pathlib import Path
manifest = Path('android/app/src/main/AndroidManifest.xml')
manifest.write_text(manifest.read_text().replace('android:label="taxi_logbook"', 'android:label="Taxi Logbuch"'))
index = Path('web/index.html')
index.write_text(index.read_text().replace('<title>taxi_logbook</title>', '<title>Taxi Logbuch</title>')
    .replace('A new Flutter project.', 'Fahrten und Umsätze einfach erfassen.'))
web_manifest = Path('web/manifest.json')
data = json.loads(web_manifest.read_text())
data.update(name='Taxi Logbuch', short_name='Logbuch', description='Dein Fahrten- und Umsatzbuch',
    background_color='#121126', theme_color='#121126')
web_manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2))
# Cloud Flutter plugins require Android API 23 or later.
gradle = Path('android/app/build.gradle.kts')
android_build = gradle.read_text().replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
# Kotlin 2.3 requires the typed compilerOptions DSL (Flutter 3.35's shell uses the old DSL).
android_build, migrated = re.subn(r'    kotlinOptions\s*\{[^}]*\}\n', '', android_build)
if migrated:
    android_build += '\nkotlin {\n    compilerOptions {\n        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)\n    }\n}\n'
gradle.write_text(android_build)
# Firebase Auth's Android dependency has Kotlin 2.3 metadata.
settings = Path('android/settings.gradle.kts')
settings.write_text(re.sub(r'(id\("org\.jetbrains\.kotlin\.android"\) version ")[^"]+(")',
    r'\g<1>2.3.0\2', settings.read_text()))
PY
flutter pub get
