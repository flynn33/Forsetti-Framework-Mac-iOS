import Foundation

public enum ModuleManagerError: Error, LocalizedError {
    case moduleNotDiscovered(String)
    case moduleLocked(String)
    case incompatible(report: CompatibilityReport)
    case notUIModule(String)

    public var errorDescription: String? {
        switch self {
        case let .moduleNotDiscovered(moduleID):
            return "Module '\(moduleID)' has not been discovered."
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
        activeUIModuleID = initialState.activeUIModuleID
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

    public func isActive(moduleID: String) -> Bool {
        enabledServiceModuleIDs.contains(moduleID) || activeUIModuleID == moduleID
    }

    public func compatibilityReport(for moduleID: String) -> CompatibilityReport? {
        guard let manifest = manifestsByID[moduleID] else {
            return nil
        }
        return compatibilityChecker.evaluate(manifest: manifest, activeUIModuleID: activeUIModuleID)
    }

    public func activateModule(moduleID: String) async throws {
        guard let manifest = manifestsByID[moduleID] else {
            throw ModuleManagerError.moduleNotDiscovered(moduleID)
        }

        let report = compatibilityChecker.evaluate(manifest: manifest, activeUIModuleID: activeUIModuleID)
        if !report.isCompatible {
            throw ModuleManagerError.incompatible(report: report)
        }

        let unlocked = await entitlementProvider.isUnlocked(moduleID: moduleID, productID: manifest.iapProductID)
        guard unlocked else {
            throw ModuleManagerError.moduleLocked(moduleID)
        }

        if manifest.moduleType == .ui,
           let currentUIModuleID = activeUIModuleID,
           currentUIModuleID != moduleID {
            try deactivateModule(moduleID: currentUIModuleID)
        }

        let module = try resolveModule(for: manifest)
        try module.start(context: context)

        switch manifest.moduleType {
        case .service:
            enabledServiceModuleIDs.insert(moduleID)
        case .ui:
            guard let uiModule = module as? ForsettiUIModule else {
                throw ModuleManagerError.notUIModule(moduleID)
            }

            activeUIModuleID = moduleID
            uiSurfaceManager.apply(moduleID: moduleID, contributions: uiModule.uiContributions)
        }

        try persistState()
        context.logger.log(.info, message: "Activated module \(moduleID)")
    }

    public func deactivateModule(moduleID: String) throws {
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
            if activeUIModuleID == moduleID {
                activeUIModuleID = nil
            }
            uiSurfaceManager.remove(moduleID: moduleID)
        }

        loadedModules[moduleID] = nil
        try persistState()
        context.logger.log(.info, message: "Deactivated module \(moduleID)")
    }

    public func restorePersistedActivation() async {
        let storedState = activationStore.loadState()

        for moduleID in storedState.enabledServiceModuleIDs {
            do {
                try await activateModule(moduleID: moduleID)
            } catch {
                context.logger.log(.warning, message: "Failed to restore service module \(moduleID): \(error.localizedDescription)")
            }
        }

        if let uiModuleID = storedState.activeUIModuleID {
            do {
                try await activateModule(moduleID: uiModuleID)
            } catch {
                context.logger.log(.warning, message: "Failed to restore UI module \(uiModuleID): \(error.localizedDescription)")
            }
        }
    }

    public func deactivateAllModules() {
        let activeModuleIDs = Set(loadedModules.keys)
        activeModuleIDs.forEach { moduleID in
            try? deactivateModule(moduleID: moduleID)
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

    private func persistState() throws {
        let state = ActivationState(
            enabledServiceModuleIDs: enabledServiceModuleIDs,
            activeUIModuleID: activeUIModuleID
        )
        try activationStore.saveState(state)
    }
}
