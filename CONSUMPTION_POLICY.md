# Forsetti Consumption Policy

## Mandatory boundary: consume the product, not the repository

**DO NOT import, copy, vendor, embed, or use the entire Forsetti repository as the starting tree of a consumer application.**
This prohibition applies even when the copied repository is left unmodified.
A request to "use Forsetti", "build on Forsetti", or "implement the Forsetti architecture" is not permission to copy its repository or recreate its internal targets.

Forsetti's supported integration surface consists of the public Swift package products listed below and the explicitly designated Xcode scaffolds. Everything else is reference material or framework-maintenance infrastructure unless this policy explicitly permits another use.

This is an engineering and supported-integration policy, not an additional license restriction. It does not amend or replace [LICENSE](LICENSE). Preserve applicable license and attribution notices when distributing permitted material.

## 1. Product allowlist: depend on these, do not copy their source

[`Package.swift`](Package.swift) declares the following public library products:

| Product | Implementation location (reference only) | Supported consumer use |
| --- | --- | --- |
| `ForsettiCore` | `Sources/ForsettiCore/` | Import public module contracts, manifests/models, registration, runtime lifecycle, compatibility, capabilities, eventing, and service contracts. |
| `ForsettiPlatform` | `Sources/ForsettiPlatform/` | Import public native service adapters and entitlement-provider implementations when needed. Depends on `ForsettiCore`. |
| `ForsettiHostTemplate` | `Sources/ForsettiHostTemplate/` | Import the reusable host bootstrap, controller, routing, and SwiftUI composition APIs when using that host. Depends on `ForsettiCore` and `ForsettiPlatform`. |

**`ForsettiHostTemplate` is a compiled library product, not a folder of source files to copy.** The copyable scaffolds live under `XcodeTemplates/`, not under `Sources/ForsettiHostTemplate/`.

`ForsettiFramework` is the package name, not an umbrella library product. Do not invent `import ForsettiFramework`, add internal targets as substitute products, or expose the example target from a consumer-side copy of `Package.swift`.

Use a normal remote SwiftPM/Xcode package dependency and explicitly select the products each consumer target needs. Keep the resolved version/revision recorded through the application's normal dependency-resolution workflow. The supplied app scaffold uses all three products; an app-owned module using only core contracts need not directly depend on the host or platform products.

A package manager may fetch/cache the repository to resolve that dependency. **A SwiftPM/Xcode-managed checkout is allowed; copying that checkout into the application's tracked source, linking unrelated targets, or bundling the repository is not.** Do not edit or commit dependency caches. Do not use `.package(path:)` pointing to a vendored Forsetti repository as an integration shortcut.

## 2. Scaffold allowlist: generate app-owned files from these templates

The approved scaffold directory is `XcodeTemplates/Project Templates/Forsetti/`:

| Template | App-owned output |
| --- | --- |
| `Forsetti App.xctemplate` | App entry point, content view, bootstrap, deployment configuration, module registry, starter app module/view, and its manifest resource. |
| `Forsetti UI Module.xctemplate` | UI module implementation, view, and manifest resource. |
| `Forsetti Service Module.xctemplate` | Service module implementation and manifest resource. |
| `Forsetti Manifest.xctemplate` | One module manifest resource. |

Install these templates into the user's Xcode template directory, or adapt only their designated scaffold source/JSON files. Resolve template placeholders, replace sample identities with app-owned identities, keep Swift descriptors and JSON manifests aligned, and preserve runtime activation checks. Generated files belong to the application; framework library sources do not.

`TemplateInfo.plist` is Xcode generation metadata, not an application resource. Neither the `.xctemplate` directories nor the installer belong in the shipping app bundle.

`Scripts/install-forsetti-xcode-template.sh` and `Scripts/uninstall-forsetti-xcode-template.sh` are development-time utilities only. A separate checkout outside the consumer source tree may be used to run them, inspect documentation, or evaluate the framework. That checkout must not become a consumer target, vendored dependency, submodule, subtree, or copied project foundation.

### SDK developer-kit delivery

The curated Forsetti SDK developer kit packages these complete templates, canonical policies/license, consumer documentation, and development-time tools alongside a separately pinned, source-based remote runtime dependency. It does not contain a second runtime source tree or prebuilt runtime binaries. SwiftPM/Xcode may still fetch framework source to compile the selected products.

The kit's `Scripts/generate-forsetti-scaffold.sh` reuses only the approved template payloads. `Scripts/verify-forsetti-integration.sh` reviews consumer content, dependency/source/resource membership, and supplied built bundles within its documented coverage. Both are development-time utilities, not application runtime or bundle assets. Keep the extracted kit outside the consumer's tracked tree. Only approved generated/adapted Swift files and app-owned manifest resources cross into application targets; required notices remain governed by their licenses.

## 3. Schematics and repository infrastructure: read, do not import

| Repository material | Classification and boundary |
| --- | --- |
| `Sources/ForsettiModulesExample/` and its manifests | Internal evaluation/test fixtures. Not a public package product and not a production module/template. Study them; author app-owned modules from the approved scaffolds instead. |
| `Tests/` | Tests of Forsetti itself. Do not copy the framework test suite into an application or add it to shipping targets. Author consumer-specific tests. |
| `framework-policy.json` | Architecture/design source material, including suggested layouts and implementation phases. A schematic, not a distributable runtime or an instruction to recreate Forsetti inside an app. |
| `README.md`, the guides, `EXECUTION_BRIEF.md`, `REPOSITORY_RULES.md`, `MODULE_BOUNDARY_RULES.md`, `implementation-policy.json`, and this policy | Development-time guidance. Read and follow applicable consumer rules; do not treat these documents as runtime configuration or bulk-copy them into an app. |
| `docs/`, downloadable wiki archives, `.forsetti/alignment/` | Documentation, historical plans, inventories, and reports. Not application assets or runtime dependencies. |
| `.github/`, `.swiftlint.yml`, guardrail/version scripts, release configuration, changelog, and repository metadata | Framework-maintenance infrastructure. Do not transplant it as the application's infrastructure. Implement app-specific checks/configuration where needed. |
| Root `Package.swift`, `Sources/`, or the repository root as a copied tree | Framework package implementation, not an application starter. Do not copy, rename, wrap, or repackage it inside the consumer project. |

License/notice files required for compliant distribution are not prohibited by this reference-only classification. Third-party dependencies and templates retain their applicable notices.

An architecture diagram, recommended folder tree, roadmap item, public declaration in a test fixture, or file's presence in this repository does not make it a supported consumer product. The public product list in `Package.swift` and this allowlist define that boundary. If a desired artifact is not listed, do not import or copy it; use a public extension point or request a reviewed update to this policy.

## 4. Required implementation sequence

1. Identify the work as framework maintenance or consumer integration. Reading Forsetti source while building an app does not turn that app into a framework-maintenance project.
2. Before edits, name the selected package products and any exact scaffold files to be generated/adapted, with their consumer destinations. Do not propose copying a directory tree from the framework.
3. Create or retain an app-owned Xcode project and app-owned module targets. Add the remote package dependency and selected public products; do not reuse the framework repository as the project.
4. Put application identities, feature code, module registrations, and manifest resources in the consumer project. Use the bundle that actually owns those manifests, not `ExampleModuleResources.bundle`.
5. Verify target dependencies, source/resource membership, and tracked files. Confirm that no framework source tree, sample target, sample resources, template metadata, wiki archive, or framework-maintenance infrastructure was copied into the app.
6. Report selected products, generated/adapted files, and verification results. Report unavailable checks honestly. A policy document is not a filesystem scanner and does not by itself prove a consumer project complies.

Framework maintenance may require cloning this repository and modifying its internals in a separate framework worktree. That is not permission to patch or vendor those internals in an application. Any temporary consumer override used to test an explicitly requested upstream framework change must remain outside the consumer tree and must not be committed as the application's integration method.

## 5. Consumer layout example

```text
MyApplication/                         # Independent app-owned repository
  MyApplication.xcodeproj/
  App/                                 # App-owned entry point and bootstrap
  Modules/                             # App-owned UI/service modules
  Resources/ForsettiManifests/          # App-owned manifest JSON
  Tests/                               # Tests of this application

Package dependency (managed by SwiftPM/Xcode, not copied into the app):
  Forsetti-Framework-Mac-iOS
    selected product: ForsettiCore
    selected product: ForsettiPlatform       # when needed
    selected product: ForsettiHostTemplate   # when using its host composition
```

**The application owns its modules. Forsetti owns its runtime. The repository contains both the product and the schematics; only the allowlisted product APIs and scaffold outputs cross into a consumer application.**
