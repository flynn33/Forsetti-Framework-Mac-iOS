import Foundation

public enum ModuleManagerError: Error, LocalizedError {
    case moduleNotDiscovered(String)
    case moduleNotActive(String)
    case moduleLocked(String)
    case incompatible(report: CompatibilityReport)
    case notUIModule(String)

    public var errorDescription: String? {
        switch self {
        case let .moduleNotDiscovered(moduleID):
            return "Module '\(moduleID)' has not been discovered."
        case let .moduleNotActive(moduleID):
            return "Module '\(moduleID)' is not active."
        case let .moduleLocked(moduleID):
            return "Module '\(moduleID)' is locked by entitlement rules."
        case let .incompatible(report):
            let details = report.issues.map(\.message).joined(separator: " | ")
            return "Module '\(report.moduleID)' is incompatible. \(details)"
        case let .notUIModule(moduleID):
            return "Module '\(moduleID)' is not a UI module."
        }
    }
}

@MainActor
public final class ModuleManager {
    public private(set) var enabledServiceModuleIDs: Set<String>
    public private(set) var enabledUIModuleIDs: Set<String>
    // Represents the UI module currently selected for foreground presentation.
    public private(set) var activeUIModuleID: String?
    public private(set) var loadedModules: [String: ForsettiModule]
    public private(set) var manifestsByID: [String: ModuleManifest]

    private let manifestLoader: ManifestLoader
    private let moduleRegistry: ModuleRegistry
    private let compatibilityChecker: CompatibilityChecker
    private let activationStore: any ActivationStore
    private let entitlementProvider: any ForsettiEntitlementProvider
    private let uiSurfaceManager: UISurfaceManager
    private let context: ForsettiContext

    public init(
        manifestLoader: ManifestLoader,
        moduleRegistry: ModuleRegistry,
        compatibilityChecker: CompatibilityChecker,
        activationStore: any ActivationStore,
        entitlementProvider: any ForsettiEntitlementProvider,
        uiSurfaceManager: UISurfaceManager,
        context: ForsettiContext
    ) {
        self.manifestLoader = manifestLoader
        self.moduleRegistry = moduleRegistry
        self.compatibilityChecker = compatibilityChecker
        self.activationStore = activationStore
        self.entitlementProvider = entitlementProvider
        self.uiSurfaceManager = uiSurfaceManager
        self.context = context

        let initialState = activationStore.loadState()
        enabledServiceModuleIDs = initialState.enabledServiceModuleIDs
        enabledUIModuleIDs = initialState.enabledUIModuleIDs
        activeUIModuleID = initialState.selectedUIModuleID
        loadedModules = [:]
        manifestsByID = [:]
    }

    @discardableResult
    public func discoverModules(
        bundle: Bundle,
        subdirectory: String = "ForsettiManifests"
    ) throws -> [ModuleManifest] {
        manifestsByID = try manifestLoader.loadManifests(bundle: bundle, subdirectory: subdirectory)
        return manifestsByID.values.sorted { $0.moduleID < $1.moduleID }
    }

    public var discoveredManifests: [ModuleManifest] {
        manifestsByID.values.sorted { $0.moduleID < $1.moduleID }
    }

    public func uiContributions(for moduleID: String) -> UIContributions? {
        guard enabledUIModuleIDs.contains(moduleID),
              let uiModule = loadedModules[moduleID] as? ForsettiUIModule else {
            return nil
        }
        return sanitizedUIContributions(for: uiModule.uiContributions)
    }

    public func isActive(moduleID: String) -> Bool {
        enabledServiceModuleIDs.contains(moduleID) || enabledUIModuleIDs.contains(moduleID)
    }

    public func compatibilityReport(for moduleID: String) -> CompatibilityReport? {
        guard let manifest = manifestsByID[moduleID] else {
            return nil
        }
        return compatibilityChecker.evaluate(manifest: manifest)
    }

    public func activateModule(moduleID: String) async throws {
        guard let manifest = manifestsByID[moduleID] else {
            throw ModuleManagerError.moduleNotDiscovered(moduleID)
        }

        let report = compatibilityChecker.evaluate(manifest: manifest)
        if !report.isCompatible {
            throw ModuleManagerError.incompatible(report: report)
        }

        let unlocked = await entitlementProvider.isUnlocked(moduleID: moduleID, productID: manifest.iapProductID)
        guard unlocked else {
            throw ModuleManagerError.moduleLocked(moduleID)
        }

        switch manifest.moduleType {
        case .service:
            try activateServiceModule(manifest: manifest, moduleID: moduleID)
        case .ui:
            try activateUIModule(manifest: manifest, moduleID: moduleID)
        }

        try persistState()
        context.logModule(.info, moduleID: moduleID, message: "Activated module")
    }

    public func deactivateModule(moduleID: String) throws {
        try deactivateModule(moduleID: moduleID, persistState: true)
    }

    public func setSelectedUIModule(moduleID: String?) throws {
        if let moduleID {
            guard manifestsByID[moduleID] != nil else {
                throw ModuleManagerError.moduleNotDiscovered(moduleID)
            }
            guard enabledUIModuleIDs.contains(moduleID) else {
                throw ModuleManagerError.moduleNotActive(moduleID)
            }
        }

        activeUIModuleID = moduleID
        try persistState()
    }

    private func deactivateModule(moduleID: String, persistState: Bool) throws {
        guard let manifest = manifestsByID[moduleID] else {
            throw ModuleManagerError.moduleNotDiscovered(moduleID)
        }

        if let module = loadedModules[moduleID] {
            module.stop(context: context)
        }

        switch manifest.moduleType {
        case .service:
            enabledServiceModuleIDs.remove(moduleID)
        case .ui:
            enabledUIModuleIDs.remove(moduleID)
            if activeUIModuleID == moduleID {
                activeUIModuleID = enabledUIModuleIDs.sorted().first
            }
            uiSurfaceManager.remove(moduleID: moduleID)
        }

        loadedModules[moduleID] = nil

        if persistState {
            try self.persistState()
        }

        context.logModule(.info, moduleID: moduleID, message: "Deactivated module")
    }

    public func restorePersistedActivation() async {
        let storedState = activationStore.loadState()

        for moduleID in storedState.enabledServiceModuleIDs {
            do {
                try await activateModule(moduleID: moduleID)
            } catch {
                context.logModule(
                    .warning,
                    moduleID: moduleID,
                    message: "Failed to restore service module",
                    metadata: ["reason": error.localizedDescription]
                )
            }
        }

        if let uiModuleID = storedState.activeUIModuleID {
            do {
                try await activateModule(moduleID: uiModuleID)
            } catch {
                context.logModule(
                    .warning,
                    moduleID: uiModuleID,
                    message: "Failed to restore UI module",
                    metadata: ["reason": error.localizedDescription]
                )
            }
        }

        for moduleID in storedState.enabledUIModuleIDs where moduleID != storedState.activeUIModuleID {
            do {
                try await activateModule(moduleID: moduleID)
            } catch {
                context.logModule(
                    .warning,
                    moduleID: moduleID,
                    message: "Failed to restore UI module",
                    metadata: ["reason": error.localizedDescription]
                )
            }
        }

        if let selectedUIModuleID = storedState.selectedUIModuleID,
           enabledUIModuleIDs.contains(selectedUIModuleID) {
            activeUIModuleID = selectedUIModuleID
        }
    }

    public func deactivateAllModules(persistState: Bool = true) {
        let activeModuleIDs = Set(loadedModules.keys)
        for moduleID in activeModuleIDs {
            do {
                try deactivateModule(moduleID: moduleID, persistState: false)
            } catch {
                context.reportModuleError(
                    moduleID: moduleID,
                    message: "Failed to deactivate module during bulk deactivation",
                    error: error
                )
            }
        }

        if persistState {
            try? self.persistState()
        }
    }

    private func resolveModule(for manifest: ModuleManifest) throws -> ForsettiModule {
        if let loadedModule = loadedModules[manifest.moduleID] {
            return loadedModule
        }

        let module = try moduleRegistry.makeModule(entryPoint: manifest.entryPoint)
        loadedModules[manifest.moduleID] = module
        return module
    }

    private func activateServiceModule(manifest: ModuleManifest, moduleID: String) throws {
        guard !enabledServiceModuleIDs.contains(moduleID) else {
            return
        }

        let module = try resolveModule(for: manifest)
        do {
            try module.start(context: context)
        } catch {
            loadedModules[moduleID] = nil
            context.reportModuleError(
                moduleID: moduleID,
                message: "Module failed to start",
                error: error,
                metadata: ["moduleType": manifest.moduleType.rawValue]
            )
            throw error
        }

        enabledServiceModuleIDs.insert(moduleID)
    }

    private func activateUIModule(manifest: ModuleManifest, moduleID: String) throws {
        guard !enabledUIModuleIDs.contains(moduleID) else {
            if activeUIModuleID == nil {
                activeUIModuleID = moduleID
            }
            return
        }

        let module = try resolveModule(for: manifest)
        guard let uiModule = module as? ForsettiUIModule else {
            loadedModules[moduleID] = nil
            throw ModuleManagerError.notUIModule(moduleID)
        }

        do {
            try module.start(context: context)
        } catch {
            loadedModules[moduleID] = nil
            context.reportModuleError(
                moduleID: moduleID,
                message: "Module failed to start",
                error: error,
                metadata: ["moduleType": manifest.moduleType.rawValue]
            )
            throw error
        }

        enabledUIModuleIDs.insert(moduleID)
        if activeUIModuleID == nil {
            activeUIModuleID = moduleID
        }
        uiSurfaceManager.apply(
            moduleID: moduleID,
            contributions: sanitizedUIContributions(for: uiModule.uiContributions)
        )
    }

    private func persistState() throws {
        let state = ActivationState(
            enabledServiceModuleIDs: enabledServiceModuleIDs,
            enabledUIModuleIDs: enabledUIModuleIDs,
            selectedUIModuleID: activeUIModuleID
        )
        try activationStore.saveState(state)
    }

    private func sanitizedUIContributions(for source: UIContributions) -> UIContributions {
        UIContributions(
            themeMask: nil,
            toolbarItems: source.toolbarItems,
            viewInjections: source.viewInjections,
            overlaySchema: source.overlaySchema
        )
    }
}
