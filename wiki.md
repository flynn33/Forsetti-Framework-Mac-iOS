# Forsetti Developer Wiki

This wiki is the comprehensive integration manual for teams using Forsetti in their own iOS/macOS projects.
It expands on `guide.md` with architecture patterns, implementation templates, governance rules, and operational playbooks.
_Last updated: February 27, 2026_

## 1. Scope and Audience

Use this document if your team is:

- Integrating Forsetti into an existing app.
- Building app-owned feature modules that plug into Forsetti.
- Setting engineering guardrails around modularity and OOP.

This document does not cover internal modification of Forsetti itself.

## 2. Integration Contract (Non-Negotiable)

Forsetti is a sealed framework for consumer apps.

Allowed:

- Use public Forsetti products and APIs.
- Build modules and host composition in your own app repository.
- Request upstream framework changes for missing extension points.

Not allowed:

- Forking Forsetti internals for app-specific behavior.
- Copying/editing Forsetti source inside your app.
- Patching runtime internals through unsupported hooks.
- Creating reverse dependencies from app code into Forsetti internals.

Decision rule: if your plan requires editing Forsetti internals, the plan is out of policy.

## 3. Core Design Principles

Forsetti integrations should preserve:

- Native-first implementation (Swift, SwiftUI where needed, Apple frameworks).
- OOP discipline (protocol contracts, dependency injection, final classes where appropriate).
- Explicit module boundaries and one-way dependency flow.
- Composition over inheritance across package boundaries.
- Low-coupling communication (event bus, service contracts, manifest metadata).

## 4. Public Concepts and Mental Model

Forsetti runtime model:

1. Your app registers module factories (`entryPoint` -> factory closure).
2. Runtime discovers module manifests from a bundle resource directory.
3. Runtime checks compatibility and entitlement rules.
4. Runtime activates service modules and at most one UI module.
5. UI contributions are surfaced via shared UI state (`UISurfaceManager`).

Key public contracts:

- `ForsettiModule`: module lifecycle contract (`start` / `stop`).
- `ForsettiUIModule`: `ForsettiModule` plus `uiContributions`.
- `ForsettiEntitlementProvider`: unlock/refresh/restore/publish entitlement state.
- `CapabilityPolicy`: capability allow/deny decision surface.
- `ActivationStore`: persistence of active module state.
- `ForsettiServiceProviding`: runtime dependency lookup boundary.

## 5. Package Integration Patterns

### 5.1 Choose Products

Minimum products:

- `ForsettiCore`

Common products:

- `ForsettiCore`
- `ForsettiPlatform`
- `ForsettiHostTemplate`

Optional sample/reference:

- `ForsettiModulesExample` (for learning, not production dependency coupling)

### 5.2 Swift Package Declaration Example

```swift
dependencies: [
    .package(url: "https://your-forsetti-repo-url", from: "0.1.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "ForsettiCore", package: "ForsettiFramework"),
            .product(name: "ForsettiPlatform", package: "ForsettiFramework"),
            .product(name: "ForsettiHostTemplate", package: "ForsettiFramework")
        ]
    )
]
```

Note: replace URL and package identity with your actual dependency source.

## 6. Recommended App Architecture

Example consumer layout:

- `MyAppHost` target: app shell and scene composition.
- `MyAppModules` target: app-owned Forsetti modules and manifests.
- `MyAppServices` target: app service implementations and adapters.
- `MyAppArchitectureTests` target: architecture and lint policy checks.

Recommended dependency direction:

- `MyAppHost` -> `MyAppModules`, `MyAppServices`, Forsetti products.
- `MyAppModules` -> Forsetti products, `MyAppServices` contracts if needed.
- `MyAppServices` -> Apple frameworks and independent app contracts.

Avoid:

- Cycles between app targets.
- Bidirectional dependencies between host and modules.
- UI framework imports in pure domain/runtime layers.

## 7. Runtime Bootstrapping

### 7.1 Manual Runtime Assembly

```swift
import ForsettiCore
import ForsettiPlatform

@MainActor
func makeRuntime(
    manifestsBundle: Bundle,
    moduleRegistry: ModuleRegistry
) -> ForsettiRuntime {
    let platformServices = DefaultForsettiPlatformServices()
    let entitlementProvider = ForsettiEntitlementProviderFactory.makeDefault()
    let capabilityPolicy = FixedCapabilityPolicy(allowedCapabilities: [.storage, .telemetry, .toolbarItems, .viewInjection])

    return ForsettiRuntime(
        services: platformServices.container,
        entitlementProvider: entitlementProvider,
        capabilityPolicy: capabilityPolicy,
        activationStore: UserDefaultsActivationStore(),
        moduleRegistry: moduleRegistry
    )
}
```

### 7.2 Host Template Assembly

```swift
import ForsettiCore
import ForsettiPlatform
import ForsettiHostTemplate

@MainActor
func makeHostController(
    manifestsBundle: Bundle,
    moduleRegistry: ModuleRegistry
) -> ForsettiHostController {
    ForsettiHostTemplateBootstrap.makeController(
        manifestsBundle: manifestsBundle,
        moduleRegistry: moduleRegistry
    )
}
```

### 7.3 SwiftUI Root

```swift
import SwiftUI
import ForsettiHostTemplate

struct ContentView: View {
    let controller: ForsettiHostController

    var body: some View {
        ForsettiHostRootView(controller: controller)
    }
}
```

## 8. Module Authoring Guide

### 8.1 Service Module Template

```swift
import ForsettiCore

public final class OrdersSyncModule: ForsettiModule {
    public let descriptor = ModuleDescriptor(
        moduleID: "com.myapp.module.orders-sync",
        displayName: "Orders Sync",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.myapp.module.orders-sync",
        displayName: "Orders Sync",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.networking, .storage, .telemetry],
        entryPoint: "OrdersSyncModule"
    )

    public init() {}

    public func start(context: ForsettiContext) throws {
        context.logger.log(.info, message: "OrdersSyncModule started")
    }

    public func stop(context: ForsettiContext) {
        context.logger.log(.info, message: "OrdersSyncModule stopped")
    }
}
```

### 8.2 UI Module Template

```swift
import ForsettiCore

public final class RewardsUIModule: ForsettiUIModule {
    public let descriptor = ModuleDescriptor(
        moduleID: "com.myapp.module.rewards-ui",
        displayName: "Rewards",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.myapp.module.rewards-ui",
        displayName: "Rewards",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.uiThemeMask, .toolbarItems, .viewInjection, .routingOverlay],
        iapProductID: "com.myapp.iap.rewards-ui",
        entryPoint: "RewardsUIModule"
    )

    public let uiContributions = UIContributions(
        toolbarItems: [
            ToolbarItemDescriptor(
                itemID: "rewards-open",
                title: "Rewards",
                systemImageName: "gift.fill",
                action: .openOverlay(routeID: "rewards.overlay")
            )
        ]
    )

    public init() {}

    public func start(context: ForsettiContext) throws {}
    public func stop(context: ForsettiContext) {}
}
```

### 8.3 Register Module Factories

```swift
import ForsettiCore

func makeRegistry() -> ModuleRegistry {
    ForsettiStaticModuleRegistry.buildRegistry { registry in
        registry.register(entryPoint: "OrdersSyncModule") { OrdersSyncModule() }
        registry.register(entryPoint: "RewardsUIModule") { RewardsUIModule() }
    }
}
```

## 9. Manifest Contract Deep Dive

Required manifest keys:

- `schemaVersion`
- `moduleID`
- `displayName`
- `moduleVersion`
- `moduleType`
- `supportedPlatforms`
- `minForsettiVersion`
- `capabilitiesRequested`
- `entryPoint`

Optional manifest keys:

- `maxForsettiVersion`
- `iapProductID`

### 9.1 Service Manifest Example

```json
{
  "schemaVersion": "1.0",
  "moduleID": "com.myapp.module.orders-sync",
  "displayName": "Orders Sync",
  "moduleVersion": { "major": 1, "minor": 0, "patch": 0, "prerelease": null },
  "moduleType": "service",
  "supportedPlatforms": ["iOS", "macOS"],
  "minForsettiVersion": { "major": 0, "minor": 1, "patch": 0, "prerelease": null },
  "maxForsettiVersion": null,
  "capabilitiesRequested": ["networking", "storage", "telemetry"],
  "iapProductID": null,
  "entryPoint": "OrdersSyncModule"
}
```

### 9.2 UI Manifest Example

```json
{
  "schemaVersion": "1.0",
  "moduleID": "com.myapp.module.rewards-ui",
  "displayName": "Rewards",
  "moduleVersion": { "major": 1, "minor": 0, "patch": 0, "prerelease": null },
  "moduleType": "ui",
  "supportedPlatforms": ["iOS", "macOS"],
  "minForsettiVersion": { "major": 0, "minor": 1, "patch": 0, "prerelease": null },
  "maxForsettiVersion": null,
  "capabilitiesRequested": ["routing_overlay", "ui_theme_mask", "toolbar_items", "view_injection"],
  "iapProductID": "com.myapp.iap.rewards-ui",
  "entryPoint": "RewardsUIModule"
}
```

### 9.3 Compatibility Checks

Forsetti evaluates:

- schema version support.
- runtime platform support.
- min/max Forsetti version range.
- capability policy decisions.
- single-active UI module behavior warnings.

A module is activatable only when the compatibility report has no error-severity issues.

## 10. UI Contributions Model

`ForsettiUIModule` can contribute:

- `themeMask`: theme tokens the host may apply.
- `toolbarItems`: actions surfaced in host toolbar.
- `viewInjections`: host slot view declarations (`slot`, `viewID`, `priority`).
- `overlaySchema`: pointers and routes for navigation/overlay behavior.

### 10.1 View Injection Pattern

Your host app should register concrete SwiftUI views by `viewID`:

```swift
import SwiftUI
import ForsettiHostTemplate

let registry = ForsettiViewInjectionRegistry()
registry.register(viewID: "rewards.banner") {
    Text("Rewards Banner")
        .padding()
}
```

Then pass this registry into `ForsettiHostRootView(controller:injectionRegistry:)`.

## 11. Entitlements and Monetization

`ForsettiEntitlementProvider` controls lock/unlock decisions:

- iOS default: `StoreKit2EntitlementProvider`.
- macOS default: static allowlist provider.

Rules:

- `iapProductID == nil` means module is considered unlocked by default.
- for paid modules, `iapProductID` must map to a product ID recognized by your entitlement provider.
- on entitlement change, runtime automatically reconciles active modules and deactivates now-locked modules.

Recommended:

- Implement restore purchases UX where paid modules are offered.
- trigger entitlement refresh on app foreground and purchase completion.

## 12. Capability Governance

Use capability policy as least-privilege control.

Example:

```swift
let policy = FixedCapabilityPolicy(
    allowedCapabilities: [.storage, .telemetry, .toolbarItems]
)
```

A denied capability becomes a compatibility error and blocks activation.

Governance suggestions:

- Define environment-specific allowlists (debug/staging/production).
- Review capability diffs in code review.
- Require explicit approval when adding new requested capabilities.

## 13. Services and Dependency Injection

Use `ForsettiServiceContainer` to provide app services to modules.

```swift
import ForsettiCore

protocol ExperimentService {
    func variant(for key: String) -> String
}

final class DefaultExperimentService: ExperimentService {
    func variant(for key: String) -> String { "control" }
}

let container = ForsettiServiceContainer()
container.register(ExperimentService.self, service: DefaultExperimentService())
```

Consume inside modules:

```swift
func start(context: ForsettiContext) throws {
    let experiments = context.services.resolve(ExperimentService.self)
    let variant = experiments?.variant(for: "checkout") ?? "unknown"
    context.logger.log(.info, message: "Variant: \(variant)")
}
```

## 14. Eventing Patterns

Use the event bus for low-coupling module interactions:

```swift
let token = context.eventBus.subscribe(eventType: "order.completed") { event in
    // react to event
}

context.eventBus.publish(
    event: ForsettiEvent(
        type: "order.completed",
        payload: ["orderID": "1234"],
        sourceModuleID: "com.myapp.module.orders-sync"
    )
)
```

Event naming guidance:

- use stable dot-separated names (`domain.action`).
- include minimal payload fields with explicit meaning.
- avoid schema-less event sprawl.

## 15. Quality Gates in Consumer Repositories

Every app using Forsetti should enforce:

- architecture policy tests (dependency/import rules).
- strict lint rules for modular/OOP constraints.
- CI blocking merges unless tests + lint pass.

### 15.1 Example Verify Script

```bash
#!/usr/bin/env bash
set -euo pipefail

swift test --parallel --enable-code-coverage
swiftlint lint --strict --config .swiftlint.yml
```

### 15.2 Example GitHub Actions Workflow

```yaml
name: Forsetti Guardrails

on:
  pull_request:
  push:

jobs:
  enforce:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - run: brew install swiftlint
      - run: ./Scripts/verify-forsetti-guardrails.sh
```

## 16. Testing Strategy

Minimum test categories:

- module lifecycle tests (`start`/`stop` behavior).
- manifest validation tests.
- compatibility policy tests (platform/version/capability).
- entitlement lock/unlock transitions.
- host UI state tests for toolbar/theme/injection contributions.

Suggested release criteria:

- zero failing tests.
- zero lint violations.
- deterministic startup with all required manifests present.

## 17. Security and Privacy Guidance

- Request only capabilities that a module truly needs.
- Avoid storing secrets in plain text storage.
- Keep telemetry payloads free from sensitive user data unless explicitly approved.
- Use least-privilege service interfaces rather than broad shared objects.

## 18. Performance and Reliability Tips

- Keep module `start` work lightweight; move heavy operations to async tasks.
- Avoid blocking main actor in UI modules.
- Ensure module `stop` is idempotent and cheap.
- Guard against duplicate event subscriptions and leaked tokens.
- Prefer deterministic registration and manifest discovery at launch.

## 19. Troubleshooting

`moduleNotDiscovered`:

- manifest missing from bundle resources.
- wrong manifests subdirectory at boot.
- manifest failed validation and was excluded.

`entryPointNotRegistered`:

- `entryPoint` in manifest does not match any registry key.
- module registration not executed before boot.

`moduleLocked`:

- module has `iapProductID` but entitlement provider does not report unlock.
- restore/refresh flow not invoked after purchase.

`incompatible`:

- unsupported platform.
- min/max Forsetti version mismatch.
- denied capability.
- schema version mismatch.

`notUIModule`:

- manifest says `moduleType = ui` but registered class conforms to `ForsettiModule` only.

## 20. Upgrade and Change Management

Before upgrading Forsetti version:

1. Review release notes and API changes.
2. Re-run compatibility checks for all manifests.
3. Execute full tests and lint in CI.
4. Validate entitlement flows on iOS and macOS.
5. Validate active UI module switching and persisted activation behavior.

For major changes:

- roll out behind feature flags where practical.
- stage rollout to internal/beta users first.
- keep rollback path to previous package version.

## 21. Pre-PR Checklist

- New code follows integration-only policy.
- No Forsetti internal source edits.
- Module manifests validated.
- Registry entries and manifest `entryPoint` values are aligned.
- Capability requests reviewed and approved.
- Entitlement behavior tested (including restore path where relevant).
- Tests/lint/CI all green.

## 22. Quick Reference

Essential order of operations:

1. Register module factories.
2. Configure entitlement provider, services, capability policy, activation store.
3. Boot runtime with manifests bundle.
4. Render host/root UI and expose module activation.
5. Monitor and reconcile entitlement changes.
6. Run guardrails before merge.
