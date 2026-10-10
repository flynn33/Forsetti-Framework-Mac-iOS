# Execution Brief

Read this before implementing or modifying a Forsetti-based application or module.

## Mandatory consumption boundary

Read [CONSUMPTION_POLICY.md](CONSUMPTION_POLICY.md) before selecting dependencies or copying files.

**DO NOT import, copy, vendor, embed, or use the entire Forsetti repository as an application starter, even unmodified.** Import only the allowlisted public package products: `ForsettiCore`, `ForsettiPlatform`, and `ForsettiHostTemplate`, as needed. Generate/adapt app-owned scaffold files only from the four designated Xcode templates.

SwiftPM/Xcode-managed dependency checkouts are allowed. Copied framework source trees, internal example targets, schematic folder layouts, tests, and repository-maintenance files are not application dependencies. State selected products and exact scaffold destinations before implementing; verify the consumer's tracked files and target/resource membership afterward.

## Framework truth

Forsetti is a modularity-first, object-oriented Apple-platform framework.

It is designed for iOS and macOS applications built in Xcode with Apple-native tools, libraries, and frameworks only.

This includes SwiftUI and Metal.

## High-risk misunderstanding to avoid

Do not misread target-level or layer-level import restrictions as global bans on Apple-native frameworks in app-owned modules.

That interpretation is wrong.

## Correct interpretation

In a multi-module single-application design:

- the application UI belongs in exactly one dedicated UI module
- that dedicated UI module may use SwiftUI and other Apple-native UI technologies
- service logic belongs in separate service modules
- Metal may be used in the correct module or layer when the module’s responsibility justifies it

## Operating rule

When deciding whether a technology is allowed, ask:

- which module owns this responsibility?
- is this the correct module or layer for this technology?

Do not ask:

- is this technology globally banned because one framework target cannot import it?

## Final reminder

Forsetti is not trying to keep you away from Apple-native frameworks.

Forsetti is trying to keep those frameworks in the correct module with strict modular boundaries.
