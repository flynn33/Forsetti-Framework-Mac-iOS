import Combine
import Foundation
import ForsettiCore

@MainActor
public final class ForsettiHostController: ObservableObject {
    @Published public private(set) var serviceModules: [ForsettiHostModuleItem] = []
    @Published public private(set) var uiModules: [ForsettiHostModuleItem] = []
    @Published public private(set) var enabledServiceModuleIDs: Set<String> = []
    @Published public private(set) var activeUIModuleID: String?
    @Published public private(set) var isBooted = false
    @Published public private(set) var isBusy = false
    @Published public private(set) var lastToolbarActionDescription: String?
    @Published public var errorMessage: String?

    public let runtime: ForsettiRuntime
    public let manifestsBundle: Bundle
    public let manifestsSubdirectory: String
    public let slotCatalog: [String]

    private let entitlementProvider: any ForsettiEntitlementProvider
    private var entitlementObservationTask: Task<Void, Never>?

    public init(
        runtime: ForsettiRuntime,
        entitlementProvider: any ForsettiEntitlementProvider,
        manifestsBundle: Bundle,
        manifestsSubdirectory: String = "ForsettiManifests",
        slotCatalog: [String] = SlotCatalog.all
    ) {
        self.runtime = runtime
        self.entitlementProvider = entitlementProvider
        self.manifestsBundle = manifestsBundle
        self.manifestsSubdirectory = manifestsSubdirectory
        self.slotCatalog = slotCatalog
    }

    public func bootIfNeeded() async {
        guard !isBooted else {
            await refreshModuleState()
            return
        }

        await boot()
    }

    public func boot(restoreActivationState: Bool = true) async {
        isBusy = true
        defer { isBusy = false }

        do {
            _ = try await runtime.boot(
                bundle: manifestsBundle,
                manifestsSubdirectory: manifestsSubdirectory,
                restoreActivationState: restoreActivationState
            )
            isBooted = true
            startEntitlementObservation()
            await refreshModuleState()
        } catch {
            present(error: error)
        }
    }

    public func shutdown() {
        entitlementObservationTask?.cancel()
        entitlementObservationTask = nil
        runtime.shutdown()

        serviceModules = []
        uiModules = []
        enabledServiceModuleIDs = []
        activeUIModuleID = nil
        isBooted = false
    }

    public func refreshModuleState() async {
        let discovered = runtime.moduleManager.discoveredManifests
        var nextItems: [ForsettiHostModuleItem] = []
        nextItems.reserveCapacity(discovered.count)

        for manifest in discovered {
            let compatibility = runtime.moduleManager.compatibilityReport(for: manifest.moduleID)
                ?? CompatibilityReport(
                    moduleID: manifest.moduleID,
                    issues: [
                        CompatibilityIssue(
                            code: .invalidSchemaVersion,
                            severity: .error,
                            message: "Module was discovered but no compatibility report is available."
                        )
                    ]
                )

            let isUnlocked = await entitlementProvider.isUnlocked(
                moduleID: manifest.moduleID,
                productID: manifest.iapProductID
            )

            let item = ForsettiHostModuleItem(
                manifest: manifest,
                compatibilityReport: compatibility,
                isUnlocked: isUnlocked,
                isActive: runtime.moduleManager.isActive(moduleID: manifest.moduleID)
            )
            nextItems.append(item)
        }

        nextItems.sort { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }

        serviceModules = nextItems.filter { $0.moduleType == .service }
        uiModules = nextItems.filter { $0.moduleType == .ui }
        enabledServiceModuleIDs = runtime.moduleManager.enabledServiceModuleIDs
        activeUIModuleID = runtime.moduleManager.activeUIModuleID
    }

    public func setServiceModuleEnabled(moduleID: String, isEnabled: Bool) async {
        isBusy = true
        defer { isBusy = false }

        do {
            if isEnabled {
                try await runtime.moduleManager.activateModule(moduleID: moduleID)
            } else {
                try runtime.moduleManager.deactivateModule(moduleID: moduleID)
            }
        } catch {
            present(error: error)
        }

        await refreshModuleState()
    }

    public func selectUIModule(moduleID: String?) async {
        isBusy = true
        defer { isBusy = false }

        do {
            if let moduleID {
                try await runtime.moduleManager.activateModule(moduleID: moduleID)
            } else if let activeUIModuleID = runtime.moduleManager.activeUIModuleID {
                try runtime.moduleManager.deactivateModule(moduleID: activeUIModuleID)
            }
        } catch {
            present(error: error)
        }

        await refreshModuleState()
    }

    public func refreshEntitlements() async {
        await entitlementProvider.refreshEntitlements()
        await refreshModuleState()
    }

    public func restorePurchases() async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await entitlementProvider.restorePurchases()
            await refreshModuleState()
        } catch {
            present(error: error)
        }
    }

    public func handleToolbarAction(_ action: ToolbarAction) {
        switch action {
        case let .navigate(pointerID):
            runtime.openPointer(pointerID)
            lastToolbarActionDescription = "Navigate pointer: \(pointerID)"
        case let .openOverlay(routeID):
            runtime.openRoute(routeID)
            lastToolbarActionDescription = "Open overlay route: \(routeID)"
        case let .publishEvent(type, payload):
            runtime.eventBus.publish(
                event: ForsettiEvent(
                    type: type,
                    payload: payload ?? [:],
                    sourceModuleID: activeUIModuleID
                )
            )
            lastToolbarActionDescription = "Published event: \(type)"
        }
    }

    public func clearError() {
        errorMessage = nil
    }

    private func startEntitlementObservation() {
        entitlementObservationTask?.cancel()
        let stream = entitlementProvider.entitlementsDidChangeStream()

        entitlementObservationTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await _ in stream {
                await self.refreshModuleState()
            }
        }
    }

    private func present(error: Error) {
        errorMessage = error.localizedDescription
    }
}
