import Foundation
import ForsettiCore

public final class ExampleServiceModule: ForsettiModule {
    public let descriptor = ModuleDescriptor(
        moduleID: "com.forsetti.module.example-service",
        displayName: "Example Service",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .service
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.forsetti.module.example-service",
        displayName: "Example Service",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.storage, .telemetry],
        iapProductID: nil,
        entryPoint: "ExampleServiceModule"
    )

    private var isStarted = false
    private let lastStartedAtStorageKey = "forsetti.example.service.lastStartedAt"

    public init() {}

    public func start(context: ForsettiContext) throws {
        guard !isStarted else {
            return
        }

        let startedAt = Date().ISO8601Format()
        if let storage = context.services.resolve(StorageService.self) {
            storage.set(startedAt, forKey: lastStartedAtStorageKey)
        }

        isStarted = true
        context.eventBus.publish(
            event: ForsettiEvent(
                type: "example.service.started",
                payload: ["moduleID": descriptor.moduleID, "startedAt": startedAt],
                sourceModuleID: descriptor.moduleID
            )
        )
        context.logger.log(.info, message: "ExampleServiceModule started")
    }

    public func stop(context: ForsettiContext) {
        guard isStarted else {
            return
        }

        if let storage = context.services.resolve(StorageService.self) {
            storage.removeValue(forKey: lastStartedAtStorageKey)
        }

        isStarted = false
        context.eventBus.publish(
            event: ForsettiEvent(
                type: "example.service.stopped",
                payload: ["moduleID": descriptor.moduleID],
                sourceModuleID: descriptor.moduleID
            )
        )
        context.logger.log(.info, message: "ExampleServiceModule stopped")
    }
}

public final class ExampleUIModule: ForsettiUIModule {
    public let descriptor = ModuleDescriptor(
        moduleID: "com.forsetti.module.example-ui",
        displayName: "Example UI",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .ui
    )

    public let manifest = ModuleManifest(
        schemaVersion: ModuleManifest.supportedSchemaVersion,
        moduleID: "com.forsetti.module.example-ui",
        displayName: "Example UI",
        moduleVersion: SemVer(major: 0, minor: 1, patch: 0),
        moduleType: .ui,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: SemVer(major: 0, minor: 1, patch: 0),
        capabilitiesRequested: [.routingOverlay, .uiThemeMask, .toolbarItems, .viewInjection],
        iapProductID: "com.forsetti.iap.example-ui",
        entryPoint: "ExampleUIModule"
    )

    public let uiContributions = UIContributions(
        themeMask: ThemeMask(
            themeID: "example.ui.theme",
            tokens: [
                ThemeToken(key: "accentColor", value: "#1479FF"),
                ThemeToken(key: "cardRadius", value: "14")
            ]
        ),
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
                slot: "home.banner",
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

    public func start(context: ForsettiContext) throws {
        guard !isStarted else {
            return
        }

        isStarted = true
        context.logger.log(.info, message: "ExampleUIModule started")
    }

    public func stop(context: ForsettiContext) {
        guard isStarted else {
            return
        }

        isStarted = false
        context.logger.log(.info, message: "ExampleUIModule stopped")
    }
}

public enum ExampleModuleRegistry {
    public static func registerAll(into registry: ModuleRegistry) {
        registry.register(entryPoint: "ExampleServiceModule") {
            ExampleServiceModule()
        }

        registry.register(entryPoint: "ExampleUIModule") {
            ExampleUIModule()
        }
    }
}
