#!/usr/bin/env bash
# Builds the web app into build/web. Extra arguments go to `flutter build web`, e.g.
#   tool/build_web.sh --base-href /BamBoozled/ --dart-define=SUPABASE_URL=...
#
# The browser database needs two files next to the app:
#   web/sqlite3.wasm    SQLite compiled for the web, downloaded from the sqlite3 package's releases
#   web/drift_worker.js the database worker, compiled from tool/drift_worker.dart
# Both are made here (and git-ignored) so they always match the package versions in pubspec.lock.
#
# The app is compiled to WebAssembly (--wasm), which draws noticeably more smoothly, especially on
# phones. Browsers that can't run it are given the JavaScript build from the same folder instead.
set -euo pipefail
cd "$(dirname "$0")/.."

version() { awk -v pkg="  $1:" '$0 == pkg {found=1} found && /version:/ {gsub(/"/, "", $2); print $2; exit}' pubspec.lock; }
SQLITE3_VERSION="$(version sqlite3)"

if [ ! -s web/sqlite3.wasm ] || [ "$(cat web/.sqlite3-version 2>/dev/null)" != "$SQLITE3_VERSION" ]; then
  echo "Downloading sqlite3.wasm for sqlite3 $SQLITE3_VERSION"
  curl -fsSL --retry 3 -o web/sqlite3.wasm \
    "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm"
  echo "$SQLITE3_VERSION" > web/.sqlite3-version
fi

dart compile js -O4 -o web/drift_worker.js tool/drift_worker.dart
rm -f web/drift_worker.js.deps web/drift_worker.js.map

flutter build web --release --wasm --no-web-resources-cdn "$@"
