# Module Authoring

The application owns module code and manifests; the remote Forsetti dependency owns runtime implementation. Begin with [the policy](../CONSUMPTION_POLICY.md) and declare selected products, exact scaffold inputs, and app-owned output destinations.

| Pattern | Approved scaffold | Ownership |
| --- | --- | --- |
| Single-module app | `Forsetti App.xctemplate` | App module owns its complete UI and application behavior. |
| Multi-module single app | `Forsetti UI Module.xctemplate` plus service scaffolds | Exactly one dedicated UI module owns app UI; service modules own separate responsibilities. |
| Service module | `Forsetti Service Module.xctemplate` | App-owned lifecycle/service behavior without primary UI contributions. |
| Manifest only | `Forsetti Manifest.xctemplate` | App-owned resource; pair it with an aligned implementation/factory. |

Generate a dedicated UI module and service module:

```bash
"$FORSETTI_SDK/Scripts/generate-forsetti-scaffold.sh" \
  --template ui --name Workspace --module-id com.example.workspace \
  --output "$FORSETTI_APP/Modules/Workspace"
"$FORSETTI_SDK/Scripts/generate-forsetti-scaffold.sh" \
  --template service --name Storage --module-id com.example.storage \
  --output "$FORSETTI_APP/Modules/Storage"
```

Add the reported Swift files and manifests to the owning app/module targets. Register each generated entry point with an app-owned `ModuleRegistry` using the corresponding factory. A module target needing core contracts selects only `ForsettiCore`; a SwiftUI view may also import Apple SwiftUI. The application host selects the additional products used by its composition.

Keep Swift descriptors, JSON `moduleID`, `entryPoint`, module type, version, requested capabilities, and runtime requirements aligned. Manifest/template schema `1.1` is separate from SDK metadata schema. Declare service/I/O, UI IDs/slots, data isolation, and default-role needs explicitly. Keep lifecycle `start` bounded and idempotent; release subscriptions and module-owned work in `stop`.

Compose services through public protocols and constructor dependency injection. Preserve module-scoped event/service access. App-owned UI or rendering modules may use SwiftUI, Metal, and other Apple-native frameworks in the responsible layer; core package import rules do not ban those technologies globally.

Use the bundle that owns the manifests, preserving the loader's `ForsettiManifests` resource directory when using the supplied bootstrap. Verify discovery and activation on the actual platform. Test rejection cases such as incompatible manifest versions or denied activation, then confirm failed modules do not render app UI.

Do not substitute internal example modules/resources for application identities. An API gap requires an upstream enhancement request, not a cache patch. Finish with source/resource membership review, the [integration verifier](Getting-Started.md#5-review-the-integration-boundary), and consumer-specific runtime tests.
