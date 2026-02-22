#!/usr/bin/env bash
set -euo pipefail

DESTINATION_TEMPLATE_DIR="$HOME/Library/Developer/Xcode/Templates/Project Templates/Forsetti/Forsetti App.xctemplate"

if [[ -d "$DESTINATION_TEMPLATE_DIR" ]]; then
  rm -rf "$DESTINATION_TEMPLATE_DIR"
  echo "Removed template: $DESTINATION_TEMPLATE_DIR"
else
  echo "Template not installed: $DESTINATION_TEMPLATE_DIR"
fi
