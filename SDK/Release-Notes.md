# Forsetti SDK @SDK_VERSION@

This first SDK release packages a curated developer kit alongside the existing source-based runtime dependency. It includes the four canonical Xcode templates, portable install/remove tools, a noninteractive scaffold generator, consumer integration verification, complete canonical policies, consumer instructions, and source-reference mappings.

The runtime publishes `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate`. Select the products each app target needs. The kit does not contain runtime sources or prebuilt XCFrameworks; SwiftPM/Xcode resolves and compiles the declared remote runtime revision.

Source commit: `@SOURCE_COMMIT@`. Runtime reference: `@RUNTIME_REF@`, resolved commit `@RUNTIME_COMMIT@`. Canonical policy provenance and each included file's hash are recorded in `sdk-manifest.json`. The metadata excludes itself from its own hash inventory. The archive checksum is published separately in `SHA256SUMS`.

Actual tested environments and acceptance results are recorded in the manifest's `verification` section. A development or unverified candidate is explicitly labeled; a release requires the recorded acceptance checks. Device compilation does not establish signed device installation or physical-device acceptance.

The generated app keeps runtime boot and activation checks ahead of production UI. Module-manifest schema/template versions remain distinct from the SDK metadata schema. Read [Compatibility](Documentation/Compatibility.md) and [Getting Started](Documentation/Getting-Started.md) before integration.
