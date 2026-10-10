# Getting Started

Read [the consumption policy](../CONSUMPTION_POLICY.md) and [consumer instructions](../AGENTS.md) first. This developer kit and the pinned remote runtime together form Forsetti SDK @SDK_VERSION@. Keep the extracted kit outside your application's tracked source and resource targets.

## 1. Create an independent project and add the runtime

Create an app-owned Multiplatform App project in Xcode. Add `@RUNTIME_URL@` with an exact revision requirement of `@RUNTIME_COMMIT@`. For the supplied app scaffold, select `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate` as target dependencies. Remove Xcode's initial app entry point/content view when adding the generated replacements so the target has exactly one `@main` entry point.

For an app-owned Swift package module that uses only core contracts:

```swift
// In your app-owned Package.swift, within dependencies:
.package(url: "@RUNTIME_URL@", revision: "@RUNTIME_COMMIT@")
// In that module target's dependencies:
.product(name: "ForsettiCore", package: "forsetti-framework-mac-ios")
```

Use the actual resolved package identity from your dependency workflow. Record `Package.resolved`; never replace the remote package with a copied framework `.package(path:)`. Do not edit package caches. Internet access is required to fetch the source-based runtime.

## 2. Generate app-owned files

Set a kit path and application path appropriate to your machine:

```bash
FORSETTI_SDK="/path/to/Forsetti-SDK-@SDK_VERSION@"
FORSETTI_APP="/path/to/My Application"
"$FORSETTI_SDK/Scripts/generate-forsetti-scaffold.sh" \
  --template app --name MyApplication \
  --module-id com.example.myapplication \
  --output "$FORSETTI_APP/App"
```

The name must be a valid Swift identifier and the module ID must use reverse-DNS segments. The generator reports exact template inputs and output files as JSON. Existing output files are rejected; use a new destination or review your existing app-owned files manually. Generate UI/service modules with `--template ui` or `--template service`, and standalone manifests with `--template manifest`.

Before generating or adapting a scaffold, name the selected products and exact input/output destinations. The generated files are your app code/resources. `TemplateInfo.plist`, `.xctemplate` directories, scripts, and kit documentation are not application assets.

## 3. Add source and resources to the app target

Add every reported Swift output to the app target's Compile Sources phase. The app scaffold supplies bootstrap, module registration, deployment configuration, module implementation/view, entry point, and content view. Keep descriptors and JSON manifests aligned when editing identities or requirements.

Add the generated `Resources/ForsettiManifests` directory as a folder reference in Copy Bundle Resources, preserving that folder name. For a macOS build, inspect `MyApplication.app/Contents/Resources/ForsettiManifests`; for iOS, inspect `MyApplication.app/ForsettiManifests`. Each contains app-owned manifest JSON. A plain source directory or Xcode group does not prove the same runtime bundle layout.

The supplied bootstrap uses `manifestsBundle: .main` and `manifestsSubdirectory: "ForsettiManifests"` because the app target owns these resources. If an app-owned module package owns resources instead, supply its resource bundle; do not use internal example-resource bundles.

## 4. Build and run

Build the app for My Mac and an iOS Simulator destination. Development mode shows the Forsetti host controls and activates eligible modules. For app-owned production UI, change the generated `DeploymentMode.current` to `.production`. The bootstrap renders the app module only after its activation succeeds. Diagnose displayed failures through the controller error and manifest/registry checks; preserve entitlement, capability, service, compatibility, and UI requirements.

Verify actual discovery, successful module activation, and your app-owned UI. Run app-specific tests. Use the [module authoring guide](Module-Authoring.md) for a dedicated UI module plus service modules.

## 5. Review the integration boundary

Keep application source in its own Git repository. Supply the built bundle and expected pinned commit:

```bash
"$FORSETTI_SDK/Scripts/verify-forsetti-integration.sh" \
  --project "$FORSETTI_APP" \
  --bundle "/path/to/MyApplication.app" \
  --runtime-commit @RUNTIME_COMMIT@ \
  --json "/path/to/integration-report.json"
```

The verifier inspects tracked content (or the available project tree when Git is absent), declared SwiftPM/Xcode dependency and source/resource membership, resolved pins when present, and supplied app bundles. It checks for framework implementation copies, internal examples, tracked dependency caches, template metadata, and framework-maintenance assets. Required license/notice files and legitimate public imports are permitted; untracked package-manager caches are excluded from app-source findings.

The report identifies examined targets, pins, resources, violations, and warnings. Static inspection cannot prove arbitrary computed Swift package declarations, custom build scripts, external resource generation, or runtime behavior. Review those inputs and run the app; a successful static report alone is not runtime or consumer compliance proof. A nonzero exit identifies violations or invalid arguments.

## Optional Xcode template installation

```bash
"$FORSETTI_SDK/Scripts/install-forsetti-xcode-template.sh"
# Temporary/custom category directory:
"$FORSETTI_SDK/Scripts/install-forsetti-xcode-template.sh" --destination "/path/with spaces/Forsetti"
"$FORSETTI_SDK/Scripts/uninstall-forsetti-xcode-template.sh" --destination "/path/with spaces/Forsetti"
```

The utilities operate only on the four Forsetti templates and locate payloads relative to the kit. They are development-time tools. Preserve [LICENSE](../LICENSE) and applicable notices when distributing permitted material.
