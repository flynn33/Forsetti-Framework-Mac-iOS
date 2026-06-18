# Phase 00 Baseline Report

## Repository State

- Branch: `alignment/apple-runtime-boundaries`
- Baseline commit: `47b774717c84e944ba50f2bb9590f9c274c6ecde`
- Initial working tree state after evidence directory creation: `.forsetti/` untracked
- Tracked source inventory: `.forsetti/alignment/baseline-file-inventory.json`
- Inventory source: `git ls-files`
- Inventory file count: 96

## Toolchain

- Swift: `Apple Swift version 6.3.2`
- Swift target: `arm64-apple-macosx26.0`
- Xcode: `26.5`, build `17F42`
- SwiftLint: `0.63.2`

## Baseline Commands

| Command | Result | Notes |
|---|---:|---|
| `git status --short` | pass | Reported `.forsetti/` as the only untracked path after evidence creation. |
| `git rev-parse --abbrev-ref HEAD` | pass | `alignment/apple-runtime-boundaries`. |
| `git rev-parse HEAD` | pass | `47b774717c84e944ba50f2bb9590f9c274c6ecde`. |
| `swift --version` | pass | Swift 6.3.2 was available. |
| `xcodebuild -version` | pass | Xcode 26.5 was available. |
| `swiftlint version` | pass | SwiftLint 0.63.2 was available. |
| `find . -name '*.json' -print0 \| xargs -0 python3 -m json.tool >/dev/null` | fail | The command passes multiple input files to `json.tool`, which accepts a single input file. |
| `find . -path './.build' -prune -o -path './.git' -prune -o -name '*.json' -print0 \| xargs -0 -n1 python3 -m json.tool >/dev/null` | pass | Corrected one-file-at-a-time JSON validation completed successfully. |
| `swift package dump-package >/tmp/forsetti-dump-package.json` | pass | Package manifest dumped successfully. |
| `swift test --parallel --enable-code-coverage` | fail | Test compilation failed in `Tests/ForsettiCoreTests/RuntimeLifecycleTests.swift`; `CountingUIModule` is missing its closing brace. |
| `swiftlint lint --strict --config .swiftlint.yml` | pass | Reported 0 violations across 50 Swift files. |
| `xcodebuild -scheme ForsettiFramework-Package -destination 'generic/platform=iOS Simulator' build` | pass | Package build succeeded for the iOS Simulator destination. |
| `./Scripts/verify-forsetti-guardrails.sh` | fail | Failed during Swift test compilation for the same `CountingUIModule` syntax error. |

## Baseline Findings

- Source builds through SwiftPM and Xcode package build paths.
- The test suite does not compile at baseline because `Tests/ForsettiCoreTests/RuntimeLifecycleTests.swift` is syntactically incomplete.
- The repository guardrail script inherits the same test compilation failure.
- Strict SwiftLint passes at baseline.
- Source JSON files validate when checked one at a time.
- Existing public guidance surfaces require neutralization in Phase 01.
