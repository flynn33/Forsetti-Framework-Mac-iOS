# Forsetti Framework Developer Guide

This guide is for teams integrating Forsetti into their own apps.
It defines the engineering rules your project should enforce so Forsetti remains modular, native, and maintainable.
_Last updated: October 10, 2026_

## Mandatory consumption boundary

Use the released Forsetti SDK developer kit and its pinned source-based runtime dependency for application onboarding. Follow the kit's Getting Started instructions and integration verifier; no framework-development checkout is required. [Maintainer packaging](docs/sdk/releasing.md) and [qualification](docs/sdk/qualification.md) remain separate repository workflows.

Read [CONSUMPTION_POLICY.md](CONSUMPTION_POLICY.md) before integration. **Do not copy, vendor, embed, or use the entire Forsetti repository as an application starter, even unmodified.** Consume only the allowlisted public package products and designated Xcode scaffold outputs. Package-manager-controlled checkouts are allowed; app-owned copies of framework library sources are not. The architecture schematics and framework-maintenance files are reference material, not an application product.

These are supported-integration rules, not additional license restrictions. [LICENSE](LICENSE) remains authoritative for license rights and required notices.

## 1. Required Stack

- Use native Apple technologies only for framework/runtime implementation:
  - Swift
  - Swift Package Manager / Xcode
  - SwiftUI (including dedicated Forsetti UI modules in application implementations)
  - Native Apple frameworks where appropriate outside `ForsettiCore`
- Do not add cross-platform UI/runtime frameworks for core behavior.

## 1b. UI Module Clarification

SwiftUI is valid for the application UI in Forsetti, but the application UI must live in the correct module.
In the multi-module single-application pattern, the application UI belongs in exactly one dedicated UI module.
That UI module may use SwiftUI and other Apple-native UI technologies.
This is a module-boundary rule, not a ban on SwiftUI.

Metal is also a valid Apple-native technology in Forsetti-based applications when it is used in the correct app-owned module or architectural layer.
Forsetti does not prohibit Metal.
Forsetti requires that Metal be used in the correct module with clear modular boundaries.

## 1c. Host UI Definition

In Forsetti documentation, "host UI" refers to the application user interface used by the app built on Forsetti.
In the multi-module single-application pattern, this application UI belongs in a dedicated UI module.
The requirement is about modular separation of responsibilities, not avoidance of Apple-native UI frameworks.

## 2. Integration Boundaries (Required)

Forsetti must be treated as the sealed runtime framework in consumer projects. Framework internals remain sealed behind public contracts, while applications and modules are built inside the runtime model.

### Allowed

- Add [Forsetti's remote package dependency](https://github.com/flynn33/Forsetti-Framework-Mac-iOS) and select only `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate` as needed by each target. Record the resolved version/revision through your app's normal dependency-resolution workflow.
- Generate or adapt app-owned files from the four approved templates under `XcodeTemplates/Project Templates/Forsetti/`.
- Build your app features in your own targets/packages.
- Implement your own modules using public contracts such as `ForsettiModule`, `ForsettiAppModule`, or `ForsettiUIModule`.

`ForsettiHostTemplate` is a compiled library product; its source directory is not a copyable scaffold. `ForsettiFramework` is the package name, not an importable umbrella product. `ForsettiModulesExample` and its resources are internal evaluation/test fixtures.

### Not Allowed

- Forking or modifying Forsetti internal targets for app-specific behavior.
- Copying framework library sources or the complete repository into your app, whether modified or unmodified; use public package products instead.
- Subclassing or patching Forsetti runtime internals through unsupported hooks.
- Coupling your app targets back into Forsetti internal targets.
- Using `.package(path:)` with a vendored Forsetti repository, or editing/committing managed dependency caches.

If a required extension point is missing, request a framework enhancement instead of patching internals.

## 3. OOP Rules (Required)

- Prefer protocol-first design for contracts and behavior boundaries.
- Use constructor dependency injection for collaborators.
- Avoid hidden global state and implicit service lookup patterns.
- Keep objects single-purpose and cohesive.
- Use `final class` for production classes unless there is a clear, documented reason not to.
- Keep access control tight:
  - `private`/`fileprivate`/`internal` by default
  - `public` only for intentional API surface

## 4. Modularity Rules (Required)

- Each module/target must own a clear responsibility.
- Do not leak platform/UI concerns into `ForsettiCore`.
- Keep public APIs minimal and stable.
- Prefer composition over inheritance across module boundaries.
- Avoid cyclic dependencies (direct or indirect).
- Use production platform defaults for app composition; keep in-memory secure storage as an explicit test/debug choice.
- Treat file export filenames as untrusted input and keep writes inside the configured export directory.

## 5. Import Restrictions

Layer-specific restrictions are enforced by lint/tests:
these are target-specific architecture guardrails, not blanket bans for every consumer module.

- `ForsettiCore` must not import:
  - `ForsettiPlatform`, `ForsettiModulesExample`, `ForsettiHostTemplate`
  - `SwiftUI`, `UIKit`, `AppKit`, `StoreKit`, `Combine`
- `ForsettiPlatform` must not import:
  - `ForsettiModulesExample`, `ForsettiHostTemplate`
  - `SwiftUI`, `UIKit`, `AppKit`
- `ForsettiModulesExample` must not import:
  - `ForsettiPlatform`, `ForsettiHostTemplate`
  - `SwiftUI`, `UIKit`, `AppKit`, `StoreKit`
- `ForsettiHostTemplate` must not import:
  - `ForsettiModulesExample`

## 6. How to Enforce These Rules in Your App

Author enforcement for your app's targets and contracts in your own repository. Framework tests, lint configuration, scripts, and CI are reference material; do not copy them into the consumer project.

- Add architecture tests in your app repo that validate:
  - allowed target dependencies
  - forbidden cross-layer imports
  - final-class policy for Forsetti-facing runtime classes
- Add a lint configuration (`.swiftlint.yml`) with custom layer/import rules.
- Add a local verification script (for example `Scripts/verify-forsetti-guardrails.sh`) that runs tests and lint in one command.
- Add CI (for example GitHub Actions) to run the same verification on every push and pull request.

Suggested structure in your app repository:

- `Tests/ArchitectureTests/ForsettiArchitecturePolicyTests.swift`
- `.swiftlint.yml`
- `Scripts/verify-forsetti-guardrails.sh`
- `.github/workflows/forsetti-guardrails.yml`

Suggested verify script commands:

```bash
swift test --parallel --enable-code-coverage
swiftlint lint --strict --config .swiftlint.yml
```

## 7. Developer Workflow (Required Before PR)

In your app repository:

1. Run your guardrail script (or equivalent test + lint commands) from repo root.
2. Confirm architecture policy tests pass.
3. Confirm lint rules pass with no violations.
4. Use a conventional PR title, such as `feat: add module registration audit` or `fix: reject stale manifest records`.
5. Open/update PR only after local guardrails pass.

PRs should be blocked from merge unless guardrails also pass in CI.

## 7b. Versioning Policy

Forsetti uses Semantic Versioning (`MAJOR.MINOR.PATCH`) for framework releases.
The repository must maintain the same framework version value in `version.txt`, `Sources/ForsettiCore/ForsettiVersion.swift`, and the README version marker. `.release-please-manifest.json` and `release-please-config.json` remain retained release configuration state.

The PR version workflow was removed on August 16, 2026. The retained `Scripts/update-pr-version.py` supports manually reviewed version updates using a supplied base version and title/body:

| Supplied title/body signal | Version result |
| --- | --- |
| non-`chore` `type!:` or `BREAKING CHANGE:` | Major bump |
| `feat:` | Minor bump |
| other supported non-`chore` types | Patch bump |
| `chore:` | No bump |

These are script classification rules, not active PR automation. `chore:` makes the script return `skipped=true` without changing version files. Review release scope and the resulting diff before committing a version update. See [versioning-and-release-automation.md](docs/versioning-and-release-automation.md) for the retained tools and historical workflow.

Release publication, tags, and changelog maintenance are separate post-merge release work.

## 8. Adding New App Code Safely (Integration-Only)

When adding capabilities in a project that uses Forsetti:

Before edits, identify the work as consumer integration and name the selected public products, any exact scaffold files to generate/adapt, and their app-owned destinations. Keep the Xcode project and module targets app-owned. Framework maintenance belongs in a separate framework checkout, not in an app-owned copy of Forsetti.

1. Create or choose an app-owned target/package for your Forsetti modules.
2. Implement `ForsettiAppModule` (single-module apps), `ForsettiUIModule` (multi-module UI), or `ForsettiModule` (service/feature) in your own codebase.
3. Define each module's descriptor/manifest and register entry points in your app bootstrap with the throwing `ModuleRegistry.register` API.
4. Compose runtime/services using public Forsetti APIs only.
5. Use manifest schema/template `1.1` for new modules and declare `runtimeRequirements` for I/O, UI, data isolation, and default-role dependencies.
6. Declare only the capabilities the module needs; service access and UI contributions are enforced against those capabilities at runtime.
7. Use `ForsettiModuleContext` in lifecycle code. Do not send, subscribe, or log as another module.
8. Keep dependencies injected and avoid global mutable state.
9. Add tests for module behavior and architecture policy in your repository.
10. Run guardrails before opening/updating a PR.
11. If an API gap is discovered, propose an upstream Forsetti change; do not patch internal framework code.

Put manifest JSON in the resource bundle that owns it and pass that bundle to discovery. The app scaffold uses `.main` because its manifests belong to the app target; a module package owning resources must supply its own bundle. Do not use `ExampleModuleResources.bundle` in a consumer app.

## 9. Review Checklist

Use this checklist for every review:

- Correct target/layer placement?
- Any forbidden imports or new cross-layer coupling?
- Public API necessary and minimal?
- Class/protocol design OOP-consistent and modular?
- Dependencies injected (not hidden globals)?
- Tests added/updated for behavior and architecture impact?
- Guardrail script executed successfully?
- Version values aligned and any manual version update reviewed?
- Selected public products and scaffold destinations documented?
- Target dependencies, source/resource membership, and tracked files verified against the consumption allowlist, with no copied framework tree, example fixtures, template metadata, or framework-maintenance infrastructure?

## 10. Non-Compliance Policy

Changes that violate these rules must be refactored before merge.
Temporary exceptions require explicit rationale in the PR description and follow-up work item.
