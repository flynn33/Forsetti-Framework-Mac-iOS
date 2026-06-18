import Foundation

extension ModuleManager {
    func validateIdentity(moduleID: String, field: String, expected: String, actual: String) throws {
        guard expected == actual else {
            throw ModuleManagerError.moduleIdentityMismatch(
                moduleID: moduleID,
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }

    func validateUIContributions(_ contributions: UIContributions, manifest: ModuleManifest) throws {
        let capabilities = Set(manifest.capabilitiesRequested)

        try requireCapability(
            .toolbarItems,
            for: manifest,
            usage: "toolbar item contributions",
            when: !contributions.toolbarItems.isEmpty,
            grantedCapabilities: capabilities
        )
        try requireCapability(
            .viewInjection,
            for: manifest,
            usage: "view injection contributions",
            when: !contributions.viewInjections.isEmpty,
            grantedCapabilities: capabilities
        )
        try requireCapability(
            .routingOverlay,
            for: manifest,
            usage: "routing overlay contributions",
            when: contributions.overlaySchema != nil,
            grantedCapabilities: capabilities
        )
        try requireCapability(
            .uiThemeMask,
            for: manifest,
            usage: "theme mask contributions",
            when: contributions.themeMask != nil,
            grantedCapabilities: capabilities
        )

        try validateDeclaredUIRequirements(contributions, manifest: manifest)
    }

    private func validateDeclaredUIRequirements(_ contributions: UIContributions, manifest: ModuleManifest) throws {
        guard manifest.manifestTemplateVersion == .v1_1 else {
            return
        }

        guard hasUIContributions(contributions) else {
            return
        }

        let requirements = try declaredUIRequirements(for: manifest)
        try validateDeclaredThemeMask(contributions.themeMask, requirements: requirements, moduleID: manifest.moduleID)
        try validateDeclaredToolbarItems(contributions.toolbarItems, requirements: requirements, moduleID: manifest.moduleID)
        try validateDeclaredViewInjections(
            contributions.viewInjections,
            requirements: requirements,
            moduleID: manifest.moduleID
        )
        try validateDeclaredOverlaySchema(contributions.overlaySchema, requirements: requirements, moduleID: manifest.moduleID)
    }

    private func hasUIContributions(_ contributions: UIContributions) -> Bool {
        contributions.themeMask != nil ||
            !contributions.toolbarItems.isEmpty ||
            !contributions.viewInjections.isEmpty ||
            contributions.overlaySchema != nil
    }

    private func declaredUIRequirements(for manifest: ModuleManifest) throws -> ModuleUIRequirements {
        guard let requirements = manifest.runtimeRequirements.ui else {
            throw ModuleManagerError.unsatisfiedRuntimeRequirement(
                moduleID: manifest.moduleID,
                reason: "UI contributions require runtimeRequirements.ui declarations."
            )
        }
        return requirements
    }

    private func validateDeclaredThemeMask(
        _ themeMask: ThemeMask?,
        requirements: ModuleUIRequirements,
        moduleID: String
    ) throws {
        guard let themeMask else {
            return
        }

        if !requirements.themeIDs.contains(themeMask.themeID) {
            throw undeclaredUIRequirement(
                moduleID: moduleID,
                value: themeMask.themeID,
                kind: "themeID"
            )
        }
    }

    private func validateDeclaredToolbarItems(
        _ toolbarItems: [ToolbarItemDescriptor],
        requirements: ModuleUIRequirements,
        moduleID: String
    ) throws {
        try requireDeclaredValues(
            toolbarItems.map(\.itemID),
            declared: requirements.toolbarItemIDs,
            moduleID: moduleID,
            kind: "toolbarItemID"
        )

        for item in toolbarItems {
            try validateDeclaredToolbarAction(item.action, requirements: requirements, moduleID: moduleID)
        }
    }

    private func validateDeclaredViewInjections(
        _ viewInjections: [ViewInjectionDescriptor],
        requirements: ModuleUIRequirements,
        moduleID: String
    ) throws {
        try requireDeclaredValues(
            viewInjections.map(\.viewID),
            declared: requirements.viewIDs,
            moduleID: moduleID,
            kind: "viewID"
        )

        try requireDeclaredValues(
            viewInjections.map(\.slot),
            declared: requirements.slotIDs,
            moduleID: moduleID,
            kind: "slotID"
        )
    }

    private func validateDeclaredOverlaySchema(
        _ overlaySchema: OverlaySchema?,
        requirements: ModuleUIRequirements,
        moduleID: String
    ) throws {
        guard let overlaySchema else {
            return
        }

        try requireDeclaredValues(
            overlaySchema.routes.map(\.routeID),
            declared: requirements.routeIDs,
            moduleID: moduleID,
            kind: "routeID"
        )
        try requireDeclaredValues(
            overlaySchema.pointers.map(\.pointerID),
            declared: requirements.pointerIDs,
            moduleID: moduleID,
            kind: "pointerID"
        )
    }

    private func validateDeclaredToolbarAction(
        _ action: ToolbarAction,
        requirements: ModuleUIRequirements,
        moduleID: String
    ) throws {
        switch action {
        case let .navigate(pointerID):
            if !requirements.pointerIDs.contains(pointerID) {
                throw undeclaredUIRequirement(moduleID: moduleID, value: pointerID, kind: "pointerID")
            }
        case let .openOverlay(routeID):
            if !requirements.routeIDs.contains(routeID) {
                throw undeclaredUIRequirement(moduleID: moduleID, value: routeID, kind: "routeID")
            }
        case .publishEvent:
            break
        }
    }

    private func requireDeclaredValues(
        _ values: [String],
        declared: [String],
        moduleID: String,
        kind: String
    ) throws {
        for value in values where !declared.contains(value) {
            throw undeclaredUIRequirement(moduleID: moduleID, value: value, kind: kind)
        }
    }

    private func undeclaredUIRequirement(moduleID: String, value: String, kind: String) -> ModuleManagerError {
        .unsatisfiedRuntimeRequirement(
            moduleID: moduleID,
            reason: "UI contribution \(kind) '\(value)' is not declared in runtimeRequirements.ui."
        )
    }

    private func requireCapability(
        _ capability: Capability,
        for manifest: ModuleManifest,
        usage: String,
        when condition: Bool,
        grantedCapabilities: Set<Capability>
    ) throws {
        guard condition, !grantedCapabilities.contains(capability) else {
            return
        }

        throw ModuleManagerError.missingCapability(
            moduleID: manifest.moduleID,
            capability: capability,
            usage: usage
        )
    }
}
