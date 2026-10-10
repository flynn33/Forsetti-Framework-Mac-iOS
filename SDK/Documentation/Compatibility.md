# Compatibility

Forsetti SDK @SDK_VERSION@ targets macOS 14 or later and iOS 17 or later, as declared by the runtime package. The package's Swift tools version is 5.10. Use Xcode with compatible Apple SDKs/toolchains. Development tools require Bash and system Python 3.9 or newer; they do not require Homebrew, Node, or third-party application runtimes.

The runtime dependency is source-based and pinned to `@RUNTIME_COMMIT@` (`@RUNTIME_REF@`). SwiftPM/Xcode downloads a managed source checkout and compiles the selected products. The ZIP contains no runtime source tree, runtime package manifest, or prebuilt XCFrameworks. Runtime resolution is not advertised as offline-capable.

| Version surface | Meaning |
| --- | --- |
| SDK/runtime `@SDK_VERSION@` | Aligned release version from canonical repository values. |
| SDK metadata `schemaVersion` | Version of the generated `sdk-manifest.json` contract. |
| Module-manifest schema `1.1` | Runtime manifest fields and validation contract. |
| Manifest-template version `1.1` | Version emitted by the approved template payloads. |
| App-owned module version | Your module's version; keep Swift/JSON declarations aligned. |

[ManifestLoader](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiCore/Runtime/ManifestLoader.swift) validates identity, schema/template versions, declared version ranges, capabilities/requirements, and role/UI boundaries. The runtime compatibility and activation paths enforce platform, Forsetti version, entitlement, capability, required services/default roles, and UI contribution requirements. Preserve these checks when adapting an app-owned scaffold.

Review the manifest's actual `verification.testedEnvironments` and acceptance checks for this assembled release. Minimum platform declarations do not establish a run on every supported OS version. An iOS device build is compilation evidence; signed installation and physical-device behavior require separate verification. SDK archive integrity and static integration checks do not establish runtime activation.

Use immutable dependency revisions and preserve resolved state. Updating to a new release requires reviewing its policy, public API, template requirements, and your app-specific tests. See [Public API](Public-API.md) and [Getting Started](Getting-Started.md).
