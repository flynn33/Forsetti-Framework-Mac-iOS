# Forsetti Framework

Forsetti is a native Apple modular runtime framework for iOS and macOS applications.
It gives host apps a consistent way to discover, validate, unlock, activate, and render feature modules while keeping architecture boundaries strict and enforceable.
_Last updated: February 27, 2026_

If you are evaluating Forsetti, start here.
If you are implementing with Forsetti, this README is the canonical high-level reference.

## Table of Contents

1. What Forsetti Is
2. The Problem It Solves
3. Design Principles
4. Integration Contract (What You Can and Cannot Do)
5. Package Structure
6. Core Runtime Concepts
7. Why Dependency Rules Are Strict
8. Import Rules and Why They Exist
9. Quick Start
10. Module Authoring Workflow
11. Manifest Contract
12. Entitlements and Paid Modules
13. Capability Governance
14. OOP and Modularity Rules
15. Architecture Guardrails (Lint, Tests, CI)
16. Recommended Consumer-Repo Guardrails
17. Troubleshooting
18. FAQ
19. Additional Documentation
20. License

## 1) What Forsetti Is

Forsetti is a framework for modular app composition.
It is built around these capabilities:

- Module discovery from bundled manifests.
- Compatibility validation before activation.
- Entitlement-aware module locking/unlocking.
- Single-active UI module policy plus service module coexistence.
- Structured UI contributions (toolbar, theme tokens, overlays, view injection).
- Native host integration with Swift and SwiftUI.

Forsetti currently targets:

- iOS
- macOS

## 2) The Problem It Solves

In many apps, feature code grows into tightly coupled systems where:

- UI and domain logic bleed into each other.
- Purchases/entitlements are bolted on late.
- Feature toggles and module activation become ad-hoc.
- “Temporary” dependencies become permanent architecture debt.

Forsetti addresses this by enforcing module contracts and runtime policy up front.
The goal is controlled extensibility without losing architectural integrity.

## 3) Design Principles

Forsetti is opinionated by design.
These principles are intentional constraints, not suggestions.

- Native-first: Swift, SwiftPM/Xcode, Apple frameworks.
- Contract-first: modules integrate through explicit protocols and manifests.
- Boundary-first: dependency direction is intentional and enforced.
- Policy-first: compatibility, capabilities, and entitlements are runtime gates.
- Host-agnostic modules: features should be plug-in style, not host-wired.

## 4) Integration Contract (What You Can and Cannot Do)

Forsetti is meant to be consumed as a sealed framework.

Allowed:

- Use Forsetti public package products and public APIs.
- Build app-owned modules in your own targets.
- Compose host runtime/services through public extension points.
- Request upstream enhancements if an extension point is missing.

Not allowed:

- Modifying Forsetti internals for app-specific behavior.
- Copying Forsetti source files into your app and patching them.
- Backdoor coupling from app targets into Forsetti internals.

Decision rule:

- If a solution requires changing Forsetti internals in your app repo, the solution is out of policy.

## 5) Package Structure

Forsetti ships as multiple products/targets with clear responsibilities:

- `ForsettiCore`
  - Runtime contracts, models, compatibility checks, activation orchestration.
  - Platform-agnostic logic only.
- `ForsettiPlatform`
  - Native platform service adapters and entitlement implementations.
- `ForsettiModulesExample`
  - Example modules + manifests for reference and testing.
- `ForsettiHostTemplate`
  - SwiftUI host controller/views for module discovery and activation UI.

## 6) Core Runtime Concepts

Forsetti flow at runtime:

1. Build a `ModuleRegistry` with entry-point factories.
2. Boot `ForsettiRuntime` with services, entitlement provider, and policy.
3. Load manifests from a bundle subdirectory.
4. Validate each manifest for compatibility/capability/version constraints.
5. Activate eligible modules.
6. Reflect UI contributions through `UISurfaceManager`.
7. React to entitlement changes and reconcile active modules.

Core contracts:

- `ForsettiModule` and `ForsettiUIModule`
- `ModuleManifest`, `ModuleDescriptor`
- `ModuleRegistry`
- `ManifestLoader`
- `CompatibilityChecker`
- `CapabilityPolicy`
- `ActivationStore`
- `ForsettiEntitlementProvider`
- `ForsettiServiceProviding` / `ForsettiServiceContainer`

## 7) Why Dependency Rules Are Strict

A rule like “X must not import Y” means:

- X is not allowed to compile against Y.
- X must remain independent of Y’s behavior and release cycle.
- Any required behavior must be expressed via contracts and dependency injection instead.

This protects:

- Stability: lower layers are insulated from upper-layer churn.
- Testability: domain/runtime can be tested without UI/store frameworks.
- Portability: core logic stays reusable across hosts.
- Build health: fewer transitive dependencies and fewer cycles.
- Team velocity: clear ownership boundaries reduce merge conflicts.

Without these rules, architectures drift into hidden coupling and regress quickly.

## 8) Import Rules and Why They Exist

These are enforced in this repo via lint/tests.
They are intentionally strict.

### `ForsettiCore` must not import:

- `ForsettiPlatform`, `ForsettiModulesExample`, `ForsettiHostTemplate`
- `SwiftUI`, `UIKit`, `AppKit`, `StoreKit`

Why:

- Core is the architecture foundation.
- If Core depends on UI/platform/commerce frameworks, every consumer inherits that coupling.
- Core must remain pure runtime/domain to stay stable and reusable.

### `ForsettiPlatform` must not import:

- `ForsettiModulesExample`, `ForsettiHostTemplate`
- `SwiftUI`, `UIKit`, `AppKit`

Why:

- Platform layer should implement service adapters, not host presentation concerns.
- Prevents “adapter layer” from drifting into app UI orchestration.

### `ForsettiModulesExample` must not import:

- `ForsettiPlatform`, `ForsettiHostTemplate`
- `SwiftUI`, `UIKit`, `AppKit`, `StoreKit`

Why:

- Example modules should demonstrate module contracts, not internal host/platform coupling.
- Keeps sample modules portable and pedagogical.

### `ForsettiHostTemplate` must not import:

- `ForsettiModulesExample`

Why:

- Host must remain generic and work with any valid module set.
- Prevents accidental hardcoding to sample implementations.

## 9) Quick Start

```swift
import ForsettiCore
import ForsettiPlatform
import ForsettiModulesExample
import ForsettiHostTemplate

let registry = ModuleRegistry()
ExampleModuleRegistry.registerAll(into: registry)

let entitlementProvider = ForsettiEntitlementProviderFactory.makeDefault(
    macOSUnlockedProductIDs: ["com.forsetti.iap.example-ui"]
)

let controller = ForsettiHostTemplateBootstrap.makeController(
    manifestsBundle: ExampleModuleResources.bundle,
    moduleRegistry: registry,
    entitlementProvider: entitlementProvider
)

let rootView = ForsettiHostRootView(controller: controller)
```

What this does:

- Registers module factories.
- Uses default entitlement provider strategy by platform.
- Builds runtime and host controller.
- Renders host UI that can discover/activate modules.

## 10) Module Authoring Workflow

In consumer apps, create your own module target and follow this sequence.

1. Define module class conforming to `ForsettiModule` or `ForsettiUIModule`.
2. Implement `descriptor` and `manifest` with aligned `moduleID` and `entryPoint`.
3. Implement lifecycle (`start`/`stop`) as idempotent, bounded operations.
4. Register module factory in your bootstrap.
5. Include manifest JSON in bundle resources.
6. Run architecture/lint/test guardrails before merge.

Guidance:

- Prefer protocol-based service lookup through `ForsettiContext.services`.
- Keep module responsibilities narrow.
- Avoid direct knowledge of host internals.

## 11) Manifest Contract

A manifest is the runtime contract for discoverability and eligibility.

Required fields:

- `schemaVersion`
- `moduleID`
- `displayName`
- `moduleVersion`
- `moduleType`
- `supportedPlatforms`
- `minForsettiVersion`
- `capabilitiesRequested`
- `entryPoint`

Optional fields:

- `maxForsettiVersion`
- `iapProductID`

If key metadata is wrong (missing entry point, invalid platform, denied capability), activation fails by design.

## 12) Entitlements and Paid Modules

Forsetti entitlement model:

- If `iapProductID` is `nil`, module is considered unlocked.
- If `iapProductID` is set, entitlement provider determines lock/unlock.
- Entitlement changes trigger active-module reconciliation.

Default provider behavior:

- iOS: StoreKit 2 backed entitlement provider.
- macOS: static allowlist provider (stub-friendly default).

Why this matters:

- Monetization state is not a UI-only concern; it is an activation policy concern.
- Enforcement at runtime layer prevents “UI says locked but runtime still active” class of bugs.

## 13) Capability Governance

Capabilities are explicit permission requests from modules.
Examples include storage, telemetry, routing overlay, toolbar items, and view injection.

Use capability policy to enforce least privilege:

- `AllowAllCapabilityPolicy` for permissive scenarios.
- `FixedCapabilityPolicy` for allowlisted scenarios.

Why enforce:

- Prevent modules from silently expanding scope.
- Make capability expansion a reviewable architecture decision.

## 14) OOP and Modularity Rules

Forsetti intentionally favors classic OOP discipline with modern Swift patterns.

Required approach:

- Protocol-first boundaries.
- Constructor dependency injection.
- Narrow public APIs.
- Strong encapsulation with `private/internal` defaults.
- `final` classes where inheritance is not a deliberate extension point.

Why:

- Reduces accidental override behavior.
- Makes coupling explicit.
- Improves deterministic behavior under modular composition.

## 15) Architecture Guardrails (Lint, Tests, CI)

This repository includes hard guardrails:

- Architecture test target for layering and class finality checks.
- Strict `SwiftLint` policy with custom layer import rules.
- CI workflow that blocks regressions on push/PR.

Run locally:

```bash
./Scripts/verify-forsetti-guardrails.sh
```

This executes:

- `swift test --parallel --enable-code-coverage`
- `swiftlint lint --strict --config .swiftlint.yml`

## 16) Recommended Consumer-Repo Guardrails

If your app consumes Forsetti, replicate guardrails in your own repository:

- Add architecture policy tests for your app targets.
- Add strict lint import/dependency rules.
- Add one local verification script that runs all checks.
- Block merges on CI unless guardrails pass.

Suggested files in consumer repo:

- `Tests/ArchitectureTests/ForsettiArchitecturePolicyTests.swift`
- `.swiftlint.yml`
- `Scripts/verify-forsetti-guardrails.sh`
- `.github/workflows/forsetti-guardrails.yml`

## 17) Troubleshooting

`moduleNotDiscovered`:

- Manifest missing from bundle resources.
- Wrong manifests subdirectory at runtime boot.
- Manifest validation failure.

`entryPointNotRegistered`:

- Manifest entry point has no matching registry factory.

`moduleLocked`:

- Entitlement provider does not currently unlock module/product.

`incompatible`:

- Platform mismatch.
- Forsetti version range mismatch.
- Denied capability.
- Schema mismatch.

`notUIModule`:

- Manifest says `moduleType = ui` but factory returns non-`ForsettiUIModule`.

## 18) FAQ

### Why so many restrictions?

Because unmanaged extensibility creates long-term coupling debt.
Forsetti optimizes for controlled modular growth, not unconstrained short-term flexibility.

### Can we bypass the import rules in a pinch?

You can technically do almost anything in code.
Architecturally, bypassing these rules is equivalent to taking dependency debt that will compound.
The framework is designed to make the correct path the easiest path.

### Why not let modules directly control host UI?

Because host composition must remain stable and reviewable.
Forsetti supports UI contributions through structured contracts instead of arbitrary host mutation.

### Why treat monetization as runtime policy?

Because lock/unlock state affects activation validity, not just visuals.
Runtime-level entitlement enforcement prevents policy drift and edge-case inconsistencies.

## 19) Additional Documentation

- `guide.md`
  - concise integration rules and policies.
- `wiki.md`
  - extended integration playbook with more implementation examples.
- `forsetti-instructions.json`
  - architecture source material and phase context.

## 20) License

Forsetti is proprietary software.

See full licensing terms in:

- `license.md`

External/commercial use requires a separate written paid license from James Daley.

## 21) Xcode Template (Optional)

This repo includes an Xcode project template for faster setup:

- Install script: `Scripts/install-forsetti-xcode-template.sh`
- Uninstall script: `Scripts/uninstall-forsetti-xcode-template.sh`

After installation, create a new project in Xcode under:

- `File > New > Project`
- `Multiplatform`
- `Forsetti App`

---

Forsetti is opinionated on purpose.
The rules are not there to reduce flexibility; they are there to preserve long-term flexibility by preventing architecture erosion.
