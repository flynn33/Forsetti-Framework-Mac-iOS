#!/usr/bin/env bash
set -euo pipefail

# Forsetti Xcode Template Installer
# Usage: ./Scripts/install-forsetti-xcode-template.sh
# Can be run from any location — the script resolves paths automatically.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_TEMPLATE_DIR="$REPO_ROOT/XcodeTemplates/Project Templates/Forsetti/Forsetti App.xctemplate"
DESTINATION_ROOT="$HOME/Library/Developer/Xcode/Templates/Project Templates/Forsetti"
DESTINATION_TEMPLATE_DIR="$DESTINATION_ROOT/Forsetti App.xctemplate"

if [[ ! -d "$SOURCE_TEMPLATE_DIR" ]]; then
  echo "Error: Source template not found at: $SOURCE_TEMPLATE_DIR" >&2
  echo "Make sure you are running this from the Forsetti repository." >&2
  exit 1
fi

mkdir -p "$DESTINATION_ROOT"
rm -rf "$DESTINATION_TEMPLATE_DIR"
cp -R "$SOURCE_TEMPLATE_DIR" "$DESTINATION_TEMPLATE_DIR"

echo ""
echo "Forsetti Xcode template installed successfully."
echo "Location: $DESTINATION_TEMPLATE_DIR"
echo ""
echo "Next steps:"
echo "  1. Quit and relaunch Xcode."
echo "  2. File > New > Project > Multiplatform > Forsetti App."
echo "  3. Add the ForsettiFramework Swift package to your new project."
echo ""
