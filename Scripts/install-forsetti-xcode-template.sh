#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_TEMPLATE_DIR="$REPO_ROOT/XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate"
DESTINATION_ROOT="$HOME/Library/Developer/Xcode/Templates/Project Templates/Forsetti"
DESTINATION_TEMPLATE_DIR="$DESTINATION_ROOT/Forsetti App.xctemplate"

if [[ ! -d "$SOURCE_TEMPLATE_DIR" ]]; then
  echo "Source template was not found at: $SOURCE_TEMPLATE_DIR" >&2
  exit 1
fi

mkdir -p "$DESTINATION_ROOT"
rm -rf "$DESTINATION_TEMPLATE_DIR"
cp -R "$SOURCE_TEMPLATE_DIR" "$DESTINATION_TEMPLATE_DIR"

echo "Installed template: $DESTINATION_TEMPLATE_DIR"
echo "Quit and relaunch Xcode, then choose: File > New > Project > Multiplatform > Forsetti App"
