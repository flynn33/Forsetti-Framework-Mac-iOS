# SDK Packaging and Release Maintenance

This is an upstream maintainer workflow. Consumers download the named Forsetti SDK asset and follow its resolved Getting Started instructions; they do not clone this repository as an application foundation.

The first SDK offering retains the source-based remote SwiftPM/Xcode runtime and packages a curated developer kit. SDK and runtime version `0.2.0` agree across `version.txt`, `ForsettiVersion.swift`, the README marker, retained release version state, and generated metadata. Module-manifest/template versions remain separate. No hosted workflows are enabled by this packaging work.

## Authoritative inputs and payload

`Scripts/package-forsetti-sdk.py` reads one identified Git source tree. Maintained SDK documents under `SDK/` have release tokens resolved during assembly. `SDK/Consumer-Instructions.md` becomes the kit's `AGENTS.md`; the repository's own `AGENTS.md` governs upstream maintenance.

The reviewed payload contains:

- SDK-specific README, consumer instructions, release notes, and five consumer documentation pages.
- Complete unchanged `CONSUMPTION_POLICY.md`, `MODULE_BOUNDARY_RULES.md`, `LICENSE`, and `NOTICE` when present.
- All four canonical template definitions and their required Swift/JSON payloads at the original Xcode template path.
- Portable template installer/uninstaller, scaffold generator, and consumer integration verifier.
- Generated metadata with exact source/runtime commits, public products/dependencies, template outputs, canonical provenance, file inventory/hashes, requirements, and actual verification results.

The archive excludes runtime `Sources/`, root runtime `Package.swift`, internal examples/resources, framework tests, architecture schematics, implementation-phase reports, wiki archives, framework instructions/configuration, release scripts/state, Git metadata, caches, signing material, and unrelated files. Packaging starts from its allowlist; it never copies the repository and deletes entries afterward. Development-only packaging helpers and the native consumer smoke harness remain in this repository.

The policy's repository-relative references remain unchanged. Generated `Documentation/Source-References.md` maps upstream-only references to immutable source URLs; the kit does not add runtime sources to satisfy those links.

## Build a candidate from a clean committed revision

Run the focused tests and repository guardrails first. A remote runtime commit must be reachable and its product/version/platform contract must match the selected source:

```bash
python3 -m unittest discover -s Tests/SDKToolTests -v
./Scripts/verify-forsetti-guardrails.sh
xcodebuild -scheme ForsettiFramework-Package \
  -destination 'generic/platform=iOS Simulator' build
FORSETTI_SOURCE=$(git rev-parse HEAD)
python3 Scripts/package-forsetti-sdk.py \
  --source-ref "$FORSETTI_SOURCE" --runtime-ref "$FORSETTI_SOURCE" \
  --output output/sdk/candidate
python3 Scripts/verify-forsetti-sdk.py \
  --archive output/sdk/candidate/Forsetti-SDK-0.2.0.zip \
  --source-repo "$PWD"
```

The candidate is labeled `unverified-candidate` until its required acceptance evidence is provided. An explicit `--development` candidate uses working inputs and is always labeled `development-candidate`; it cannot certify source equality or become a release. A clean source is mandatory for release output. Publish a source checkpoint only within the owner's authorization so clean consumers can resolve the immutable remote dependency.

Extract the candidate outside the framework worktree, restore script executable permissions when using an extractor that does not preserve ZIP modes, and follow [qualification](qualification.md). Keep logs, runtime receipts, bundle inspection, and screenshots in an external test directory or ignored `output/`. Never substitute a local package override or hidden maintainer example for the declared remote dependency.

## Record measured acceptance

The packaging report is a JSON file with `version`, `sourceCommit`, `runtimeCommit`, `testedEnvironments`, and `checks`. Each check has a unique `name`, a `status` of `passed`, `failed`, or `not-run`, and concrete `details` pointing to commands/evidence. Record actual macOS, Xcode, Swift, simulator/runtime, and architecture values; do not infer supported-platform coverage from a manifest parse.

Required release check names are `payload`, `tools`, `generated-source`, `clean-consumer`, `macos-runtime`, `ios-simulator-runtime`, `multimodule-runtime`, `rejection-runtime`, `ios-device-build`, `integration-boundary`, `getting-started`, `relevant-tests`, and `lint`. A failed check prevents release status. The native harness supplies the consumer-related results; maintainers combine them with actual payload/tool/test/lint/usability results. Do not mark a check passed merely to satisfy metadata.

Both canonical policy files must match the recorded source blobs byte-for-byte. Extracted scripts must work without a development checkout. Missing/extra payloads, tampered hashes, product drift, unsafe symlinks, unresolved placeholders, mutable dependencies, overwrites, and deliberately noncompliant consumer fixtures are negative tests.

## Assemble and verify final assets

After qualification, use the same clean source/runtime revision and the measured report. A release tag must be signed, immutable by maintenance policy, verified, and resolve to that exact qualified source; creating/pushing it requires the owner's publication authorization.

```bash
git tag -s v0.2.0 "$FORSETTI_SOURCE" -m 'Forsetti SDK 0.2.0'
git verify-tag v0.2.0
git push origin refs/tags/v0.2.0
python3 Scripts/package-forsetti-sdk.py \
  --source-ref v0.2.0 --runtime-ref v0.2.0 \
  --verification-report /path/to/qualification.json \
  --output output/sdk/release
python3 Scripts/verify-forsetti-sdk.py \
  --archive output/sdk/release/Forsetti-SDK-0.2.0.zip \
  --source-repo "$PWD"
```

Inspect the manifest's release status and measured evidence before publishing. Packaging produces the ZIP and an external `SHA256SUMS`. Metadata excludes itself from its own hash inventory, and the ZIP checksum remains outside the ZIP. ZIP paths are sorted and timestamps/permissions normalized. Repeating assembly with identical source, runtime reference, and report must produce identical bytes. A different existing artifact is rejected; use a fresh output directory rather than overwriting a published release.

Publish the separately named ZIP and checksum as release assets, with accurate release notes and a qualified source/tag. GitHub's automatic source-code ZIP/tarball is not the SDK. Read back the release author, tag/target, asset names, and downloaded asset hashes; compare local/tracking/live refs. Update the README, docs, live wiki, and its downloadable snapshot. Archive/distribution publication is distinct from signed physical-device installation.

## Scope and limits

The consumer verifier reports tracked files, declared membership, pins, supplied bundles, warnings, and its static-analysis limitations. Public imports and required notices are permitted; untracked managed caches are excluded, while tracked/cache target members are violations. Review custom build scripts and computed declarations separately, and run actual apps. A verified ZIP or static report alone is not runtime acceptance.

Preserve unrelated local work and existing release artifacts. No new distribution repository, automatic paid workflow, runtime binary conversion, or proprietary license change is part of this release.
