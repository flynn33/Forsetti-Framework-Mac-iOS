# Consumer Integration Instructions

**You are integrating Forsetti into an independent application, not developing the Forsetti framework. Read CONSUMPTION_POLICY.md first. Import only the approved public products. Generate or adapt only the designated scaffold outputs. Do not copy, vendor, reconstruct, patch, or use the framework repository as the application's starting tree, even unmodified. The application owns its modules; Forsetti owns its runtime implementation.**

Before edits, report the chosen runtime products, exact approved template input files, and app-owned output destinations. Use the immutable remote dependency in `sdk-manifest.json`; record its resolved commit in the application's dependency workflow. A managed SwiftPM/Xcode checkout is permitted. Vendored local-path dependencies, dependency-cache edits, submodules/subtrees containing the framework, and copied framework targets are not supported integration methods.

Generate app-owned files with this kit's generator or install its four approved Xcode templates. Replace sample identities, keep module descriptors/JSON/registry entry points aligned, and preserve activation gating. Template metadata, tools, policies, and documentation do not enter shipping app resource phases.

A single-module app owns its UI in its `ForsettiAppModule`. A multi-module single application has exactly one dedicated `ForsettiUIModule`, plus service modules as needed. App-owned UI/rendering modules may use SwiftUI, Metal, and appropriate Apple-native frameworks in their owning layers. Internal Forsetti target import restrictions are not global technology bans. Use protocol boundaries, constructor dependency injection, and native Swift/SwiftUI composition.

Load manifests from the bundle that owns them. Verify the built resource layout, not just the source folder. Use the production platform entitlement defaults and explicit public service/activation APIs. Do not render module UI before successful activation, suppress failures, or substitute a permissive debug provider to make production wiring pass.

Before completion, report target dependencies, source/resource membership, tracked copied-file checks, built bundle inspection, and actual build/runtime results. Run the supplied integration verifier with the app bundle and immutable runtime commit, plus consumer-specific tests. Its coverage is described in [Getting Started](Documentation/Getting-Started.md). Report missing tooling or checks honestly.

A missing extension point requires a reviewed upstream request, not a patch to runtime internals or dependency caches. Required license/notice material remains governed by [LICENSE](LICENSE). Reference-only policy paths are mapped in [Source References](Documentation/Source-References.md).
