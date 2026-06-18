import Foundation
import ForsettiCore

public final class ExampleServiceModule: ForsettiModule {
    public static let moduleID = "com.forsetti.module.example-service"
    public static let entryPoint = "ExampleServiceModule"

    public let descriptor = ModuleDescriptor(
        moduleID: ExampleServiceModule.moduleID,
        displayName: "Example Service",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .service
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: ExampleServiceModule.moduleID,
        displayName: "Example Service",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.storage, .telemetry],
        iapProductID: nil,
        entryPoint: ExampleServiceModule.entryPoint,
        runtimeRequirements: ModuleRuntimeRequirements(
            io: [
                ModuleIORequirement(
                    requirementID: "example-service.storage.last-started",
                    kind: .storage,
                    access: .readWrite,
                    required: false
                ),
                ModuleIORequirement(
                    requirementID: "example-service.telemetry.lifecycle",
                    kind: .telemetry,
                    access: .emit,
                    required: false
                )
            ],
            dataIsolation: ModuleDataIsolation(
                mode: .privateToModule,
                ownedStoreIDs: ["example-service"]
            )
        )
    )

    private var isStarted = false
    private let lastStartedAtStorageKey = "forsetti.example.service.lastStartedAt"

    public init() {}

    public func start(context: any ForsettiModuleContext) throws {
        guard !isStarted else {
            return
        }

        let startedAt = Date().ISO8601Format()
        if let storage = context.services.resolve(StorageService.self) {
            storage.set(startedAt, forKey: lastStartedAtStorageKey)
        }

        isStarted = true
        context.publishEvent(
            type: "example.service.started",
            payload: ["moduleID": descriptor.moduleID, "startedAt": startedAt]
        )
        context.logger.info("ExampleServiceModule started")
    }

    public func stop(context: any ForsettiModuleContext) {
        guard isStarted else {
            return
        }

        if let storage = context.services.resolve(StorageService.self) {
            storage.removeValue(forKey: lastStartedAtStorageKey)
        }

        isStarted = false
        context.publishEvent(
            type: "example.service.stopped",
            payload: ["moduleID": descriptor.moduleID]
        )
        context.logger.info("ExampleServiceModule stopped")
    }
}

public final class ExampleUIModule: ForsettiUIModule {
    public static let moduleID = "com.forsetti.module.example-ui"
    public static let entryPoint = "ExampleUIModule"

    public let descriptor = ModuleDescriptor(
        moduleID: ExampleUIModule.moduleID,
        displayName: "Example UI",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .ui
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: ExampleUIModule.moduleID,
        displayName: "Example UI",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.routingOverlay, .toolbarItems, .viewInjection],
        iapProductID: "com.forsetti.iap.example-ui",
        entryPoint: ExampleUIModule.entryPoint,
        defaultModuleRole: .ui,
        runtimeRequirements: ModuleRuntimeRequirements(
            ui: ModuleUIRequirements(
                viewIDs: ["example-banner", "example-overlay-view"],
                slotIDs: ["module.workspace", "overlay.main"],
                toolbarItemIDs: ["example-ui-home"],
                routeIDs: ["example-overlay"],
                pointerIDs: ["home"]
            )
        )
    )

    public let uiContributions = UIContributions(
        toolbarItems: [
            ToolbarItemDescriptor(
                itemID: "example-ui-home",
                title: "Overlay",
                systemImageName: "square.stack.3d.up",
                action: .openOverlay(routeID: "example-overlay")
            )
        ],
        viewInjections: [
            ViewInjectionDescriptor(
                injectionID: "example-ui-banner",
                slot: "module.workspace",
                viewID: "example-banner",
                priority: 100
            )
        ],
        overlaySchema: OverlaySchema(
            schemaID: "example.ui.overlay-schema",
            pointers: [
                NavigationPointer(
                    pointerID: "home",
                    label: "Home",
                    target: BaseDestinationRef(destinationID: "home"),
                    presentation: .inline
                )
            ],
            routes: [
                OverlayRoute(
                    routeID: "example-overlay",
                    path: "/example/overlay",
                    destination: .moduleOverlay(viewID: "example-overlay-view", slot: "overlay.main")
                )
            ]
        )
    )

    private var isStarted = false

    public init() {}

    public func start(context: any ForsettiModuleContext) throws {
        guard !isStarted else {
            return
        }

        isStarted = true
        context.logger.info("ExampleUIModule started")
    }

    public func stop(context: any ForsettiModuleContext) {
        guard isStarted else {
            return
        }

        isStarted = false
        context.logger.info("ExampleUIModule stopped")
    }
}

public enum ExampleModuleRegistry {
    public static func registerAll(into registry: ModuleRegistry) throws {
        try registry.register(entryPoint: ExampleServiceModule.entryPoint) {
            ExampleServiceModule()
        }

        try registry.register(entryPoint: ExampleUIModule.entryPoint) {
            ExampleUIModule()
        }
    }
}
