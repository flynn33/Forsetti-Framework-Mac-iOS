# Public API

Select public runtime products through the pinned dependency. The kit does not supply a second runtime implementation. Source links below refer to the immutable release source and are reference material.

| Product | Public integration surface |
| --- | --- |
| `ForsettiCore` | Module protocols, descriptors/manifests, `ModuleRegistry`, `ForsettiRuntime`, lifecycle/compatibility/capability contracts, service/event contracts, and structured UI contribution models. |
| `ForsettiPlatform` | `DefaultForsettiPlatformServices` and `ForsettiEntitlementProviderFactory` for native production composition. |
| `ForsettiHostTemplate` | `ForsettiHostTemplateBootstrap`, `ForsettiHostController`, `ForsettiHostRootView`, routing catalogs, and the view injection registry used by the approved app scaffold. |

`ForsettiFramework` is the package name, not an import. Internal examples and implementation details do not become public SDK extension points merely because their declarations are visible in repository source.

## Module contracts and registration

[Module protocols](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiCore/Protocols/ForsettiProtocols.swift) define `ForsettiModule` with a descriptor, manifest, `start(context:) throws`, and `stop(context:)`. Lifecycle context uses the public `ForsettiModuleContext` contract. `ForsettiUIModule` adds structured UI contributions; `ForsettiAppModule` represents a single-module application containing its UI.

[ModuleRegistry](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiCore/Runtime/ModuleRegistry.swift) maps manifest entry-point strings to factories. `register(entryPoint:replacingExisting:factory:)` throws for duplicate entries unless replacement is explicitly selected. Use app-owned factories and keep their descriptor/manifest identity aligned with bundled JSON.

## Boot and activation

[ForsettiRuntime.boot](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiCore/Runtime/ForsettiRuntime.swift) discovers manifests from the supplied owning bundle, refreshes entitlements, and optionally restores activation. Activation uses the module manager's public methods; successful discovery alone is not successful activation.

[ForsettiHostTemplateBootstrap.makeController](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiHostTemplate/Controller/ForsettiHostTemplateBootstrap.swift) composes native platform services, runtime, UI surface management, and the host controller. Supply the actual manifest bundle and subdirectory. [ForsettiHostController](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiHostTemplate/Controller/ForsettiHostController.swift) supports explicit launch activation strategies and exposes boot/activation state and errors. Check successful activation before presenting module UI; the approved app scaffold performs that check.

## Native services and entitlement composition

[ForsettiEntitlementProviderFactory.makeDefault](@RUNTIME_URL@/blob/@RUNTIME_COMMIT@/Sources/ForsettiPlatform/EntitlementProviders.swift) selects StoreKit 2 on iOS and a static entitlement provider on macOS. Configure real product/module identities for your application. Do not use debug entitlement overrides in production wiring. Request service extension needs through public contracts and constructor composition, rather than copying or patching runtime internals.

Manifests are bundled metadata describing compiled-in modules; they are not a mechanism for downloading and executing arbitrary native code. See [Module Authoring](Module-Authoring.md), [Compatibility](Compatibility.md), and the complete [Module Boundary Rules](../MODULE_BOUNDARY_RULES.md).
