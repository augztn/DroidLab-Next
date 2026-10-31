#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/apps/desktop"
flutter create --project-name droidlab_desktop --platforms=linux,windows,macos .
flutter pub get
