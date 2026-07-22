# Forsetti Framework

Forsetti is a native Apple modular runtime framework for iOS and macOS applications.
It gives host apps a consistent way to discover, validate, unlock, activate, and render feature modules while keeping architecture boundaries strict and enforceable.
_Last updated: June 20, 2026_

**Current Version: 0.1.4** <!-- x-release-please-version -->

[View Changelog](CHANGELOG.md) | [All Releases](https://github.com/flynn33/Forsetti-Framework-Mac-iOS/releases)

---

If you are evaluating Forsetti, start here.
If you are implementing with Forsetti, this README is the canonical high-level reference.

## Table of Contents

1. What Forsetti Is
2. Who This Is For
3. The Problem It Solves
4. Design Principles
5. Integration Contract (What You Can and Cannot Do)
6. Package Structure
7. Core Runtime Concepts
8. Why Dependency Rules Are Strict
9. Import Rules and Why They Exist
10. Quick Start
11. Module Authoring Workflow
12. Manifest Contract
13. Entitlements and Paid Modules
14. Capability Governance
15. OOP and Modularity Rules
16. Architecture Guardrails (Lint, Tests, CI)
17. Recommended Consumer-Repo Guardrails
18. Versioning and Release Automation
19. Troubleshooting
20. FAQ
21. Additional Documentation
22. License
23. Xcode Templates (Production Starter)

## 1) What Forsetti Is

Forsetti is a framework for modular app composition.
It is built around these capabilities:

- Module discovery from bundled manifests.
- Compatibility validation before activation.
- Entitlement-aware module locking/unlocking.
- Flexible module activation with clear deployment patterns (see below).
- Structured UI contributions (toolbar, theme tokens, overlays, view injection).
- Native host integration with Swift and SwiftUI.

Forsetti currently targets:

- iOS
- macOS

### Framework Identity Clarification

Forsetti is a modularity-first, object-oriented framework for building iOS and macOS applications in Xcode using Apple-native tools, libraries, and frameworks only.
This includes Swift, SwiftUI, Metal, and other Apple-native technologies used in the correct module or architectural layer.

## 2) Who This Is For

Forsetti is designed for:

- **Teams building monetized iOS and macOS apps** that need clean module boundaries, entitlement-gated features, and scalable architecture.
- **Solo developers shipping modular applications** who want runtime governance without building custom infrastructure.
- **Organizations managing multi-app portfolios** that want a shared modular runtime across products.

Forsetti is open source under the Apache License, Version 2.0. See [LICENSE](LICENSE) and section 22 for details.

If you are evaluating Forsetti, start with the Quick Start (section 10) and the Xcode templates (section 23).

## 3) The Problem It Solves

In many apps, feature code grows into tightly coupled systems where:

- UI and domain logic bleed into each other.
- Purchases/entitlements are bolted on late.
- Feature toggles and module activation become ad-hoc.
- “Temporary” dependencies become permanent architecture debt.

Forsetti addresses this by enforcing module contracts and runtime policy up front.
The goal is controlled extensibility without losing architectural integrity.

## 4) Design Principles

Forsetti is opinionated by design.
These principles are intentional constraints, not suggestions.

- Native-first: Swift, SwiftPM/Xcode, Apple frameworks.
- Contract-first: modules integrate through explicit protocols and manifests.
- Boundary-first: dependency direction is intentional and enforced.
- Policy-first: compatibility, capabilities, and entitlements are runtime gates.
- Host-agnostic modules: features should be plug-in style, not host-wired.

## 4b) Deployment Patterns

Forsetti supports four deployment patterns. Choose the one that matches your use case.

### Pattern A — Single-Module App (most common)

The app is a single `ForsettiAppModule` that includes the complete application UI.
The framework loads silently in the background.
End users see only the module's UI and have no awareness of the framework.
Framework controls (Home, Settings) are hidden in production.
Framework errors go silently to the framework error log.
Updates are delivered by swapping the module with a new version.

> This is the expected pattern for the vast majority of apps built on Forsetti.

### Pattern B — Multi-Module Single Application

The application is composed of multiple modules: exactly one UI module plus one or more service modules.
The UI module carries the application's UI.
All service modules run simultaneously alongside the UI module.
The framework enforces one active UI module at a time for this pattern.
The framework still runs silently; end users see only the UI module's interface.

In the multi-module single-application pattern, the application is composed of exactly one dedicated UI module plus one or more service modules.
The dedicated UI module carries the application's user interface.
That UI module may use SwiftUI and other Apple-native UI frameworks and tools.
Service modules remain separate from the UI module.

> Use this pattern when your application requires background services (data sync, analytics, etc.) that are cleanly separated from the UI.

### Pattern C — Developer Testing (multiple single-module apps)

A developer loads multiple different single-module apps on one framework instance for testing.
Each module represents a separate application and may have its own UI.
Only one module is active at a time since each represents a different application.
Framework controls (Home, Settings, module switcher) remain visible so the developer can switch between apps.

> This is a development and QA pattern, not intended for production deployment.

### Pattern D — Dashboard Deployment (end-user multi-app)

Multiple separate applications are hosted on one framework for end-user access.
Framework controls may remain visible to allow users to navigate between applications.
A dedicated UI module for the dashboard itself is recommended.

> Use this pattern for portal or launcher-style apps where end users explicitly switch between multiple applications.

## 5) Integration Contract (What You Can and Cannot Do)

Forsetti is the sealed runtime framework. Framework internals are sealed behind public contracts, while applications and modules are built inside the Forsetti runtime model through manifests, registration, entitlements, compatibility, capability-scoped services, framework-mediated communication, and structured UI contribution contracts.

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

## 6) Package Structure

Forsetti ships as multiple products/targets with clear responsibilities:

- `ForsettiCore`
  - Runtime contracts, models, compatibility checks, activation orchestration.
  - Platform-agnostic logic only.
- `ForsettiPlatform`
  - Native platform service adapters and entitlement implementations.
- `ForsettiHostTemplate`
  - SwiftUI host controller/views for module discovery and activation UI.
- `ForsettiModulesExample`
  - Internal reference/test target with example modules and manifests. It is not exposed as a public package product.

## 7) Core Runtime Concepts

Forsetti flow at runtime:

1. Build a `ModuleRegistry` with entry-point factories.
2. Boot `ForsettiRuntime` with services, entitlement provider, and policy.
3. Load manifests from a bundle subdirectory.
4. Validate each manifest for compatibility/capability/version constraints.
5. Restore prior activation state or explicitly activate selected modules.
6. Reflect UI contributions through `UISurfaceManager`.
7. React to entitlement changes and reconcile active modules.

Core contracts:

- `ForsettiModule`, `ForsettiAppModule`, and `ForsettiUIModule`
- `ModuleManifest`, `ModuleDescriptor`
- `ModuleRegistry`
- `ManifestLoader`
- `CompatibilityChecker`
- `CapabilityPolicy`
- `ActivationStore`
- `ForsettiEntitlementProvider`
- `ForsettiServiceProviding` / `ForsettiServiceContainer`

Platform defaults:

- `DefaultForsettiPlatformServices` uses Apple-native networking, storage, Keychain-backed secure storage, local file export, and telemetry placeholders.
- `InMemorySecureStorageService` remains available for explicit tests/debug composition only.
- `LocalFileExportService` sanitizes suggested filenames and writes only inside its configured export directory.

## 8) Why Dependency Rules Are Strict

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

## 9) Import Rules and Why They Exist

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

Important clarification:
Layer and target import restrictions in Forsetti are architectural boundary rules.
They are not global bans on Apple-native frameworks in app-owned modules.
A consumer application may build app-owned Forsetti-compatible modules in its own targets and may use Apple-native frameworks that are appropriate to each module's responsibility, provided those frameworks are used in the correct module or architectural layer.

## 10) Quick Start

Forsetti has two intentionally different starting paths:

- Repository-local evaluation path: uses the internal `ForsettiModulesExample` target to inspect framework behavior quickly.
- Production starter path: uses the Forsetti Xcode templates to generate app-owned module scaffolding.

If you are preparing a real application, start with section 23 and `xcode-template-guide.md`.

```swift
import ForsettiCore
import ForsettiPlatform
import ForsettiHostTemplate

let registry = ModuleRegistry()
try MyAppModuleRegistry.registerAll(into: registry)

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
- Renders host UI that can discover modules and activate them through explicit launch or user action.

### Debug / Test Entitlements

For development and testing, use `makeDebug` to bypass StoreKit:

```swift
// Unlock everything (all modules treated as purchased):
let debugProvider = ForsettiEntitlementProviderFactory.makeDebug()

// Unlock specific modules/products only:
let selectiveProvider = ForsettiEntitlementProviderFactory.makeDebug(
    unlockedProductIDs: ["com.yourapp.iap.premium"]
)
```

Pass the debug provider to `ForsettiHostTemplateBootstrap.makeController(entitlementProvider:)`.
Use `StaticEntitlementProvider.setUnlockedProducts(_:)` to change unlock state at runtime during tests.

## 11) Module Authoring Workflow

In consumer apps, create your own module target and follow this sequence.

1. Define module class conforming to `ForsettiAppModule` (single-module apps), `ForsettiUIModule` (multi-module UI), or `ForsettiModule` (service/feature).
2. Implement `descriptor` and `manifest` with aligned `moduleID` and `entryPoint`.
3. Implement lifecycle (`start`/`stop`) as idempotent, bounded operations.
4. Register module factory in your bootstrap.
5. Include manifest JSON in bundle resources.
6. Run architecture/lint/test guardrails before merge.

Guidance:

- Prefer protocol-based service lookup through `ForsettiModuleContext.services`.
- Use `context.logger`, `context.publishEvent(type:payload:)`, and `context.sendMessage(to:type:payload:)` from module lifecycle code.
- Keep module responsibilities narrow.
- Avoid direct knowledge of host internals.
- For multi-module single applications, keep the application UI in a dedicated UI module. That UI module may use SwiftUI and other appropriate Apple-native frameworks.

## 12) Manifest Contract

A manifest is the runtime contract for discoverability and eligibility.

Required fields:

- `schemaVersion`
- `manifestTemplateVersion`
- `moduleID`
- `displayName`
- `moduleVersion`
- `moduleType`
- `supportedPlatforms`
- `minForsettiVersion`
- `capabilitiesRequested`
- `entryPoint`
- `runtimeRequirements`

Optional fields:

- `maxForsettiVersion`
- `iapProductID`
- `defaultModuleRole`

Current generated manifests use schema/template `1.1`.
Existing `1.0` manifests still decode with safe defaults: no I/O requirements, no UI requirements, private data isolation, and no default module role.

Discovery creates framework-owned registration records from manifests.
Activation fails by design when key metadata is wrong, a registration record is missing or stale, a capability is denied, a required I/O/default-role provider is unavailable, or UI contributions exceed declared UI requirements.

## 13) Entitlements and Paid Modules

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

## 14) Capability Governance

Capabilities are explicit permission requests from modules.
Examples include storage, telemetry, routing overlay, toolbar items, view injection, shared database, authentication, diagnostics, API, and security.

Use capability policy to enforce least privilege:

- `AllowAllCapabilityPolicy` for permissive scenarios.
- `FixedCapabilityPolicy` for allowlisted scenarios.

Why enforce:

- Service resolution is scoped to the active module's granted capabilities.
- UI contributions are accepted only when the module has the matching UI capability.
- Prevent modules from silently expanding scope.
- Make capability expansion a reviewable architecture decision.

## 15) OOP and Modularity Rules

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

## 16) Architecture Guardrails (Lint, Tests, CI)

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

GitHub Actions also enforce:

- `guardrails.yml`: package tests, architecture checks, SwiftLint, JSON validation, and iOS Simulator build coverage.
- `lint-pr.yml`: conventional pull request title format.
- `pr-version.yml`: SemVer version updates for non-`chore` pull requests.

## 17) Recommended Consumer-Repo Guardrails

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

## 18) Versioning and Release Automation

Forsetti uses Semantic Versioning (`MAJOR.MINOR.PATCH`) across the PR-updated framework version surfaces:

- `version.txt`
- `Sources/ForsettiCore/ForsettiVersion.swift`
- the visible README version marker

`.release-please-manifest.json` remains retained release configuration state and is not changed by the PR version workflow.

Pull request titles use conventional commit-style prefixes. The PR version workflow derives the next SemVer from the PR title and body:

| PR signal | Version bump |
| --- | --- |
| `type!:` or `BREAKING CHANGE:` in the PR body | Major |
| `feat:` | Minor |
| other supported non-`chore` types | Patch |
| `chore:` | No version change |

This means documentation, CI, tests, fixes, refactors, performance work, and build changes all advance the framework version unless the PR is explicitly a repository chore. Chore PRs are reserved for maintenance that should not represent a framework version change, and the workflow fails a chore PR when version files already differ from the target branch.

Release publication, changelog maintenance, tags, and GitHub releases remain a separate post-merge release process.

## 19) Troubleshooting

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

- Manifest says `moduleType = ui` or `moduleType = app` but factory returns a type that does not conform to `ForsettiUIModule` or `ForsettiAppModule`.

`moduleIdentityMismatch`:

- Registry factory returned a module whose descriptor or bundled manifest does not match the discovered manifest identity, type, version, or entry point.

`missingCapability`:

- Module tried to contribute UI or resolve a service without the required declared/granted capability.

## 20) FAQ

### Why so many restrictions?

Because unmanaged extensibility creates long-term coupling debt.
Forsetti optimizes for controlled modular growth, not unconstrained short-term flexibility.

### Can we bypass the import rules in a pinch?

You can technically do almost anything in code.
Architecturally, bypassing these rules is equivalent to taking dependency debt that will compound.
The framework is designed to make the correct path the easiest path.

### Is Metal allowed in Forsetti-based applications?

Metal is an allowed Apple-native technology in Forsetti-based applications when it is used in the correct app-owned module or architectural layer.
For example, a rendering-oriented module may use Metal where that module's responsibility justifies it.
Metal is not prohibited by Forsetti; it is governed by modular boundaries and correct placement.

### Why not let modules directly control host UI?

Because host composition must remain stable and reviewable.
Forsetti supports UI contributions through structured contracts instead of arbitrary host mutation.

### Why treat monetization as runtime policy?

Because lock/unlock state affects activation validity, not just visuals.
Runtime-level entitlement enforcement prevents policy drift and edge-case inconsistencies.

### What about performance at scale or offline?

See the [Performance and Reliability](https://github.com/flynn33/Forsetti-Framework-Mac-iOS/wiki/Security-Privacy-and-Reliability#performance-and-reliability) wiki section for detailed guidance on cold-start overhead, larger module counts, and offline entitlement behavior.
In short: keep module `start()` fast, keep manifest files small, and rely on StoreKit's local receipt cache for offline entitlement resilience.

## 21) Additional Documentation

- `developer-guide.md`
  - canonical integration rules and policies.
- `docs/versioning-and-release-automation.md`
  - SemVer rules, PR version workflow behavior, and release automation ownership.
- `guide.md`
  - redirect to `developer-guide.md`.
- [GitHub Wiki](https://github.com/flynn33/Forsetti-Framework-Mac-iOS/wiki)
  - comprehensive architecture, runtime, workflow, and integration documentation.
- [Downloadable wiki archive](docs/wiki/Forsetti-Framework-Mac-iOS-wiki-pages.zip)
  - zipped snapshot of the published wiki pages.
- `framework-policy.json`
  - architecture source material, runtime policy, and phase context.
- `IMPLEMENTATION_GUIDE.md`
  - canonical implementation guidance for developers and reviewers.
- `MODULE_BOUNDARY_RULES.md`
  - concise boundary rules that separate internal target guardrails from consumer module implementation.
- `xcode-template-guide.md`
  - template ownership model, generated structure, and production-starter workflow.

## 22) License

This project is licensed under the Apache License, Version 2.0.
Copyright 2026 James Daley.

See [LICENSE](LICENSE) for the full terms.

## 23) Xcode Templates (Production Starter)

The Xcode template set is a first-class Forsetti onboarding path for production applications.

### Starter App vs Example App

- `Forsetti App.xctemplate` is the production starter path.
  It generates app-owned bootstrap/config files, an app-owned starter module, a starter module registry, and starter manifest resources.
- `ForsettiModulesExample` remains in this repository for evaluation and learning.
  It is sample-only content, is not exposed as a public package product, and is not the default identity of template-generated applications.

### Included Templates

- `Forsetti App.xctemplate`
  - Generates app bootstrap, deployment mode config, module registry, app module, app module view, and `Resources/ForsettiManifests`.
- `Forsetti UI Module.xctemplate`
  - Generates a UI module scaffold suitable for Pattern A UI iteration or Pattern B UI module implementation.
- `Forsetti Service Module.xctemplate`
  - Generates a service/background module scaffold suitable for Pattern B multi-module applications.
- `Forsetti Manifest.xctemplate`
  - Generates a starter Forsetti module manifest JSON file.

### Install Templates

Option A: script install (recommended)

```bash
./Scripts/install-forsetti-xcode-template.sh
```

Option B: manual install

1. Copy `XcodeTemplates/Project Templates/Forsetti/` to:
   `~/Library/Developer/Xcode/Templates/Project Templates/Forsetti/`
2. Restart Xcode.

### Create a Starter Project

1. File > New > Project > Multiplatform.
2. Choose `Forsetti App`.
3. Add the `ForsettiFramework` Swift package to your app target.
4. Add package products: `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate`.

### Ownership Model (summary)

- App-owned files: generated app bootstrap, deployment mode configuration, module registry, module implementation, and module view.
- Framework-owned files: Forsetti package internals (`Sources/ForsettiCore`, `Sources/ForsettiPlatform`, `Sources/ForsettiHostTemplate`) in this repository.

### Recommended Pattern to Start

Most teams should start with Pattern A (single app-owned module), then move to Pattern B when service modules are needed.
Use deployment mode configuration in the generated app to move from developer controls to production behavior.

For full template guidance, see `xcode-template-guide.md`.

To uninstall templates: `Scripts/uninstall-forsetti-xcode-template.sh`

---

Forsetti is opinionated on purpose.
The rules are not there to reduce flexibility; they are there to preserve long-term flexibility by preventing architecture erosion.
