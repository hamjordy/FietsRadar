#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is not installed or is not on PATH." >&2
  exit 1
fi

if [[ ! -d android ]]; then
  flutter create . --no-pub --platforms=android --project-name=fietsradar --org=nl.fietsradar
fi

manifest="android/app/src/main/AndroidManifest.xml"
if [[ ! -f "$manifest" ]]; then
  echo "Expected Android manifest was not generated: $manifest" >&2
  exit 1
fi

python3 - "$manifest" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
permissions = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_FINE_LOCATION",
]
missing = [
    f'    <uses-permission android:name="{permission}" />'
    for permission in permissions
    if f'android:name="{permission}"' not in content
]
if missing:
    marker = "    <application"
    if marker not in content:
        raise SystemExit("Could not locate <application> in AndroidManifest.xml")
    content = content.replace(marker, "\n".join(missing) + "\n" + marker, 1)
    path.write_text(content, encoding="utf-8")
PY

# flutter create generates a sample widget test for a demo MyApp. This app has its own focused tests.\nrm -f test/widget_test.dart\n\necho "Android platform files and GPS permissions are ready."
