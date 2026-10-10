# Source References

The complete canonical policies in this kit are copied byte-for-byte from source commit `@SOURCE_COMMIT@`. Their relative links retain repository semantics. Runtime source and framework-maintenance materials referenced there are intentionally absent from the curated kit.

The following immutable links resolve upstream-only policy references. They are reference material, not SDK payload additions or consumer-copy permissions. Local policy/boundary/license files and the four template directories are included in this development kit; template metadata and tools do not belong in shipping application resources.

| Canonical policy reference | Immutable upstream location |
| --- | --- |
| `Package.swift` | [Public product declarations](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Package.swift) |
| `Sources/ForsettiCore/` | [Core implementation](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/Sources/ForsettiCore) |
| `Sources/ForsettiPlatform/` | [Native adapter implementation](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/Sources/ForsettiPlatform) |
| `Sources/ForsettiHostTemplate/` | [Compiled host library implementation](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/Sources/ForsettiHostTemplate) |
| `Sources/ForsettiModulesExample/` | [Internal evaluation/test fixtures](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/Sources/ForsettiModulesExample) |
| `Tests/` | [Framework tests](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/Tests) |
| `framework-policy.json` | [Architecture schematics/history](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/framework-policy.json) |
| `README.md` and guides | [Framework repository entry point](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/README.md), [developer guide](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/developer-guide.md), [implementation guide](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/IMPLEMENTATION_GUIDE.md), [template guide](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/xcode-template-guide.md), [redirect guide](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/guide.md) |
| `EXECUTION_BRIEF.md` | [Maintainer/execution guidance](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/EXECUTION_BRIEF.md) |
| `REPOSITORY_RULES.md` | [Framework maintenance rules](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/REPOSITORY_RULES.md) |
| `implementation-policy.json` | [Machine-readable maintainer/consumer rules](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/implementation-policy.json) |
| `docs/` and wiki archives | [Repository documentation](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/docs) |
| `.forsetti/alignment/` | [Historical inventories/reports](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/.forsetti/alignment) |
| `.github/` | [Repository maintenance metadata](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/.github) |
| `.swiftlint.yml` | [Framework lint configuration](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/.swiftlint.yml) |
| Guardrail/version scripts | [Framework guardrail script](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/verify-forsetti-guardrails.sh), [version script](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/update-pr-version.py) |
| Release configuration | [Retained configuration](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/release-please-config.json), [retained version state](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/.release-please-manifest.json) |
| Changelog/repository metadata | [Change history](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/CHANGELOG.md), [repository tree](@RUNTIME_URL@/tree/@SOURCE_COMMIT@) |
| Canonical policy/boundary/license | [Consumption policy](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/CONSUMPTION_POLICY.md), [module boundaries](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/MODULE_BOUNDARY_RULES.md), [license](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/LICENSE) |
| Approved templates and install/remove utilities | [Template source directory](@RUNTIME_URL@/tree/@SOURCE_COMMIT@/XcodeTemplates/Project%20Templates/Forsetti), [installer](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/install-forsetti-xcode-template.sh), [uninstaller](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/uninstall-forsetti-xcode-template.sh) |
| SDK generation/integration utilities | [Scaffold generator](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/generate-forsetti-scaffold.sh), [integration verifier](@RUNTIME_URL@/blob/@SOURCE_COMMIT@/Scripts/verify-forsetti-integration.sh) |

The runtime product dependency is pinned separately in `sdk-manifest.json` to `@RUNTIME_REF@`, resolved commit `@RUNTIME_COMMIT@`. File inventory/provenance hashes record the exact packaged bytes. No unlisted upstream artifact becomes a supported consumer product through this reference map.
