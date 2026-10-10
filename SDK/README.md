# Forsetti SDK @SDK_VERSION@

**You are integrating Forsetti into an independent application, not developing the Forsetti framework. Read CONSUMPTION_POLICY.md first. Import only the approved public products. Generate or adapt only the designated scaffold outputs. Do not copy, vendor, reconstruct, patch, or use the framework repository as the application's starting tree, even unmodified. The application owns its modules; Forsetti owns its runtime implementation.**

The SDK offering consists of this curated developer kit plus the pinned, source-based SwiftPM/Xcode runtime dependency. The kit contains approved templates, portable development tools, and consumer documentation. Runtime libraries are compiled by SwiftPM/Xcode from the remote dependency; they are not prebuilt binaries in this ZIP. Network access to the declared dependency is required.

Use one onboarding path:

1. Create an independent app-owned Xcode project. Add `@RUNTIME_URL@` at exact revision `@RUNTIME_COMMIT@` and retain Xcode's `Package.resolved` through your normal dependency workflow.
2. Select `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate` for the supplied app scaffold. Select only the products other targets need; a module using core contracts needs only `ForsettiCore` directly.
3. Run `Scripts/generate-forsetti-scaffold.sh --template app --name MyApplication --module-id com.example.myapplication --output "/path/to/My Application/App"`. Add the resulting Swift files and manifest resources to the app target.
4. Keep the generated module registry and Swift/JSON identities aligned. Include `Resources/ForsettiManifests` as a folder resource so the built app contains `ForsettiManifests/*.json`; inspect the actual bundle after building.
5. Build and run the app. Development mode exposes module controls. Switch the generated deployment mode to `.production` for app-owned UI, which waits for successful runtime activation.
6. Run `Scripts/verify-forsetti-integration.sh --project "/path/to/My Application" --bundle "/path/to/MyApplication.app" --runtime-commit @RUNTIME_COMMIT@` and review the report alongside your app tests.

Follow [Getting Started](Documentation/Getting-Started.md) for complete commands and resource membership. The scripts locate their own kit, so they work regardless of the current directory, including paths containing spaces. They require Bash and system Python 3.9 or newer; Apple-platform builds require Xcode.

| Runtime product | Direct dependencies | Select for |
| --- | --- | --- |
| `ForsettiCore` | None | Module contracts, manifests, registration, lifecycle, compatibility, capabilities, events, and service contracts. |
| `ForsettiPlatform` | `ForsettiCore` | Native service adapters and entitlement-provider implementations. |
| `ForsettiHostTemplate` | `ForsettiCore`, `ForsettiPlatform` | Supplied host bootstrap, controller, routing, and SwiftUI composition. |

`ForsettiFramework` is the package name, not an umbrella import. `ForsettiHostTemplate` is a compiled library product; its implementation sources are not copyable app scaffolds. Internal examples are not SDK products.

The complete canonical [Consumption Policy](CONSUMPTION_POLICY.md) and [Module Boundary Rules](MODULE_BOUNDARY_RULES.md) are included unchanged. Some canonical policy links refer to repository-only paths absent from this kit. [Source References](Documentation/Source-References.md) maps those references to immutable upstream URLs. Those links are reference material, not instructions to import additional repository content.

Read [Public API](Documentation/Public-API.md), [Module Authoring](Documentation/Module-Authoring.md), [Compatibility](Documentation/Compatibility.md), and [Release Notes](Release-Notes.md). The integration verifier checks declared memberships, tracked content, and supplied bundles; its documented limits do not replace runtime testing or review of dynamic build configuration.

The policies, template directories, metadata, installer, generator, and verifier belong to the development kit. Only generated/adapted app-owned Swift files and manifest resources enter app targets. Preserve required [license](LICENSE) and notice material according to its terms; the supported-integration policy does not amend those terms.
