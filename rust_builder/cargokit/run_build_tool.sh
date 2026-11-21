#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd "$(dirname "$0")/build_tool" && pwd -P)"
work="$CARGOKIT_TOOL_TEMP_DIR/locked_tool"
mkdir -p "$work"
cp "$source_dir/pubspec.yaml" "$source_dir/pubspec.lock" "$work/"
cp -R "$source_dir/lib" "$source_dir/bin" "$work/"
cd "$work"
dart_bin="${FLUTTER_ROOT:+$FLUTTER_ROOT/bin/cache/dart-sdk/bin/}dart"
"$dart_bin" pub get --offline --enforce-lockfile --no-precompile || "$dart_bin" pub get --enforce-lockfile --no-precompile
exec "$dart_bin" bin/build_tool.dart "$@"
