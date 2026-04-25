# Changelog

All notable changes to Forsetti Framework are documented in this file.

## Unreleased

### Added

- Added production starter Xcode templates for app modules, UI modules, service modules, and standalone module manifests.
- Added starter module files for app, UI, and service module authoring, including module manifests and SwiftUI views.
- Added `DeploymentMode` and template-local module registry support for template-created Forsetti app projects.
- Added `xcode-template-guide.md` with installation, removal, and template usage guidance.

### Changed

- Moved comprehensive wiki documentation to the GitHub Wiki as the canonical long-form documentation surface.
- Rebuilt the Forsetti App Xcode template around an app module entry point instead of embedding application behavior directly in bootstrap code.
- Updated template installation and uninstallation scripts for the expanded Xcode template set.
- Expanded README coverage for the production starter templates and template-based app/module authoring workflow.

### Removed

- Removed automated wiki publishing, documentation-release tagging, and source-splitting workflow files.
- Removed the repository-local wiki source file now that the GitHub Wiki is maintained directly.
- Removed tracked SwiftPM build products and Xcode workspace state from the repository.

## Documentation Release docs-v2 - 2026-04-11

### Added

- Added implementation guidance for consumers integrating Forsetti into application projects.
- Added a focused contributor brief for repository rules, expected workflows, and review boundaries.
- Added module boundary rules documentation covering allowed dependency directions and integration limits.

### Changed

- Clarified the README, developer guide, implementation guide, wiki source, and project instruction files for the second documentation release.
- Expanded the coding policy JSON with stronger repository invariants and documentation expectations.
- Tightened language around Forsetti as an Apple-native modular runtime, with clearer guidance on host apps, modules, and framework boundaries.

## Documentation Release docs-v1 / Version Baseline 0.1.0 - 2026-03-04

### Added

- Added release automation with Release Please configuration, version manifest data, and `version.txt`.
- Added documentation release automation for `docs-vN` tags and GitHub documentation releases.
- Added pull request title linting for conventional commit-style PR titles.
- Added README version references and release links for version `0.1.0`.

### Changed

- Updated `ForsettiVersion.current` to align the framework version with `0.1.0`.
- Updated `.gitignore` to exclude `.DS_Store`, SwiftPM build products, SwiftPM workspace metadata, and wiki output pages.

## Initial Development - 2026-02-22 to 2026-03-03

### Added

- Added the SwiftPM package structure for `ForsettiCore`, `ForsettiPlatform`, `ForsettiModulesExample`, and `ForsettiHostTemplate`.
- Added core runtime contracts for manifests, modules, registries, compatibility checks, activation state, entitlements, services, eventing, logging, and UI contributions.
- Added host-template controller, catalog, overlay routing, view injection, and SwiftUI shell components.
- Added example service and UI modules with bundled Forsetti manifests.
- Added platform service and entitlement provider implementations.
- Added architecture, core runtime, host template, and platform test targets.
- Added guardrail scripts and CI workflow coverage for package tests, SwiftLint, architecture checks, and template installation checks.
- Added wiki publishing workflow support and a source-splitting script for README, guide, developer guide, and wiki source documents.
- Added proprietary licensing documentation and README licensing guidance.
- Added coding policy JSON and repository instruction metadata.

### Changed

- Hardened manifest loading with duplicate detection, subdirectory validation, and malformed manifest coverage.
- Hardened module activation and deactivation around compatibility failures, entitlement state, persisted activation, lifecycle cleanup, and runtime shutdown.
- Moved default platform services into the core service container so service dependencies remain injectable.
- Expanded runtime tests for compatibility checks, manifest loading, lifecycle behavior, module communication, module logging, UI surface management, and host controller behavior.
- Reworked the shell UI and runtime model to support active UI module selection alongside multiple enabled service modules.
- Expanded README, guide, developer guide, wiki source, and instruction documents to describe runtime invariants, deployment patterns, host integration, and module boundaries.
- Updated Xcode template bootstrap behavior to register template modules and align with the runtime entry point model.
- Added factory coverage for platform entitlement providers and improved template installation guidance.

### Fixed

- Corrected README module naming and documentation references.
- Corrected runtime and host-template naming around app modules and UI modules.
- Corrected module manager and host controller handling for selected UI modules.

### Removed

- Removed `.DS_Store` from the repository.
