#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

echo "==> Validating repository JSON files..."
find . \
  -path './.git' -prune -o \
  -path './.build' -prune -o \
  -path './.swiftpm' -prune -o \
  -name '*.json' -print0 |
  xargs -0 -n1 python3 -m json.tool >/dev/null

echo "==> Checking repository guidance surfaces..."
term_one="Co-authored""-by"
term_two="Generated"" by"
term_three="generated"" by"
term_four="authored"" by"
term_five="Authored"" by"
term_six="Chat""GPT"
term_seven="Open""AI"
term_eight="Cod""ex"
term_nine="AI""-assisted"
term_ten="AI"" generated"
term_eleven="AI""-generated"
term_twelve="ag""entic"
term_thirteen="AI"" coding"
term_fourteen="AI"" ag""ents"

prohibited_pattern="$term_one|$term_two|$term_three|$term_four|$term_five|$term_six|$term_seven|$term_eight|$term_nine|$term_ten|$term_eleven|$term_twelve|$term_thirteen|$term_fourteen"

if rg -n "$prohibited_pattern" --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!.swiftpm/**' \
  --glob '!.forsetti/**' .; then
  echo "Repository guidance surfaces contain prohibited attribution terms." >&2
  exit 1
fi

bad_path_terms=("Cod""ex" "ag""entic" "ag""ent" "Chat""GPT" "Open""AI" "l""lm")
for term in "${bad_path_terms[@]}"; do
  if find . \
    -path './.git' -prune -o \
    -path './.build' -prune -o \
    -path './.swiftpm' -prune -o \
    -path './.forsetti' -prune -o \
    -type f -iname "*$term*" -print | grep -q .; then
    echo "Repository file names contain prohibited attribution terms." >&2
    exit 1
  fi
done

echo "==> Running Swift tests (includes architecture enforcement tests)..."
swift test --parallel --enable-code-coverage

echo "==> Running SwiftLint with Forsetti guardrails..."
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is not installed. Install with: brew install swiftlint" >&2
  exit 1
fi

swiftlint lint --strict --config .swiftlint.yml

echo "==> Forsetti guardrails passed."
