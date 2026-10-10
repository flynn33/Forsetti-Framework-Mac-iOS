# SDK Qualification Procedure

Qualify the extracted curated SDK and its declared immutable remote runtime. The generated consumer projects must live outside the framework worktree. These are consumer-specific test apps, not distributable framework fixtures or a second runtime implementation.

## Baseline and environment

Record the clean source commit, SDK/runtime version, OS/Xcode/Swift versions, native architectures, available simulator runtime, and free disk space. Prior framework checks recorded 81 passing XCTest cases, strict SwiftLint, and an iOS Simulator package build before SDK implementation. Run the new SDK tooling suite and relevant framework checks for the release source; that earlier baseline does not certify this SDK.

Use a temporary template installation destination. Test all four templates, repeated install/remove, unrelated-template preservation, paths containing spaces, invalid identities, missing/extra payloads, and overwrite/path protections. The focused Python suites retain these cases. Do not modify a developer's real Xcode template directory during qualification.

## Extracted payload

Run `Scripts/verify-forsetti-sdk.py` against the produced ZIP and external checksum, with `--source-repo` for recorded Git-source equality. Extract it and inspect exact files and executable modes. Verify both canonical policies and all template payloads against their recorded source, and exercise missing/extra/hash/symlink negative fixtures.

Package the same source/runtime/report twice into separate fresh output directories and compare final ZIP/checksum bytes. SDK-local links must resolve; unchanged policy references absent from the payload must be explicitly mapped to immutable upstream URLs.

## Independent native consumers

`Scripts/test-forsetti-sdk-consumer.py` is a maintainer-only harness using Python standard library, Git, native `plutil`, Xcode, and `simctl`. It calls the extracted generator and writes an independent app-owned Xcode project. Its dependency is the metadata's remote URL and full commit; no local package override, internal example module, source checkout, or framework fixture supplies app/runtime content.

Prepare a dedicated simulator/device set and an external work directory with spaces. The harness CLI is:

```bash
python3 Scripts/test-forsetti-sdk-consumer.py \
  --sdk "/path/with spaces/Forsetti-SDK-0.2.0" \
  --workdir "/path/with spaces/Native Consumer Verification" \
  --runtime-commit "$FORSETTI_SOURCE" \
  --simulator "$FORSETTI_SIMULATOR" \
  --device-set "/path/to/DedicatedSimulators" \
  --report "/path/to/native-consumer-results.json"
```

The harness creates source/resource phases and preserves `Resources/ForsettiManifests` as a folder resource. It records Xcode's actual `Package.resolved` pin and checks built resource paths. App-owned test instrumentation observes the normal bootstrap/controller/module-manager state and module view appearance; it does not bypass activation or change framework code.

Run these variants on actual macOS and iOS Simulator:

1. Generated single app module in production mode: manifests discovered, entry points registered, intended module active, and generated app-owned view observed.
2. Generated dedicated UI module plus generated service module: exactly the expected UI module active with its service module; host/registry adaptations remain app-owned and use public APIs.
3. Invalid manifest-schema rejection: boot error reported, production state fails, no active UI module, and module UI is not shown.

Build the single-app iOS device configuration without signing when supported. Report that as compilation only. Signed device installation and physical-device acceptance are separate and are not implied by this test.

## Boundary and usability

Run the extracted consumer verifier against each project and supplied built app bundles with the expected runtime commit. Inspect tracked content, resolved dependency, selected public products, declared source/resource membership, manifest identity/contents, and built resources. Run compliant and deliberately noncompliant fixtures, including renamed/copied runtime sources, tracked caches, internal examples, mutable/mismatched pins, stale built manifests, local runtime overrides, and template/maintenance assets in app resources.

Follow the packaged Getting Started procedure, including app-owned identities, generated registry, exact dependency/products, target/resource membership, and production gating. Inspect the rendered app-owned UI and rejection screen. Save runtime JSON receipts, commands, logs, and screenshots. Record which OS/toolchain versions were actually exercised; minimum declarations are not full deployment-matrix evidence.

Combine native results with payload/tool/reproducibility/usability/framework-test/lint evidence using the report contract in [release maintenance](releasing.md). If tooling or runtime execution is unavailable, record `not-run`, keep candidate status, and list exact missing commands/reasons. Publish a release only after its required checks pass under the owner's authorization.
