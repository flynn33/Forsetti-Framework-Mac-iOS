import Foundation
import XCTest
@testable import ForsettiCore

@MainActor
final class RuntimeRequirementEnforcementTests: XCTestCase {
    func testActivationSucceedsWhenRequiredTelemetryServiceIsAvailable() async throws {
        let services = ForsettiServiceContainer()
        services.register(TelemetryService.self, service: RuntimeRequirementTelemetryService())
        let manager = try makeManager(
            manifests: [RuntimeRequiredTelemetryModule.moduleManifest],
            registrations: [
                RuntimeRequiredTelemetryModule.entryPoint: { RuntimeRequiredTelemetryModule() }
            ],
            services: services
        )

        try await manager.activateModule(moduleID: RuntimeRequiredTelemetryModule.moduleID)

        XCTAssertTrue(manager.enabledServiceModuleIDs.contains(RuntimeRequiredTelemetryModule.moduleID))
    }

    func testActivationFailsWhenRequiredDefaultRoleProviderIsMissing() async throws {
        let manager = try makeManager(
            manifests: [RuntimeSharedDatabaseConsumerModule.moduleManifest],
            registrations: [
                RuntimeSharedDatabaseConsumerModule.entryPoint: { RuntimeSharedDatabaseConsumerModule() }
            ]
        )

        do {
            try await manager.activateModule(moduleID: RuntimeSharedDatabaseConsumerModule.moduleID)
            XCTFail("Expected unsatisfiedRuntimeRequirement.")
        } catch {
            guard case let ModuleManagerError.unsatisfiedRuntimeRequirement(moduleID, reason) = error else {
                return XCTFail("Expected unsatisfiedRuntimeRequirement, received \(error).")
            }
            XCTAssertEqual(moduleID, RuntimeSharedDatabaseConsumerModule.moduleID)
            XCTAssertTrue(reason.contains("shared_database"))
        }
    }

    func testActivationSucceedsWhenRequiredDefaultRoleProviderIsAvailable() async throws {
        let manager = try makeManager(
            manifests: [
                RuntimeSharedDatabaseConsumerModule.moduleManifest,
                RuntimeSharedDatabaseProviderModule.moduleManifest
            ],
            registrations: [
                RuntimeSharedDatabaseConsumerModule.entryPoint: { RuntimeSharedDatabaseConsumerModule() },
                RuntimeSharedDatabaseProviderModule.entryPoint: { RuntimeSharedDatabaseProviderModule() }
            ]
        )

        try await manager.activateModule(moduleID: RuntimeSharedDatabaseConsumerModule.moduleID)

        XCTAssertTrue(manager.enabledServiceModuleIDs.contains(RuntimeSharedDatabaseConsumerModule.moduleID))
    }

    func testUndeclaredUIContributionFailsActivation() async throws {
        let manifest = RuntimeDeclaredToolbarUIModule.moduleManifest(declaredToolbarItemIDs: [])
        let manager = try makeManager(
            manifests: [manifest],
            registrations: [
                RuntimeDeclaredToolbarUIModule.entryPoint: { RuntimeDeclaredToolbarUIModule(manifest: manifest) }
            ]
        )

        do {
            try await manager.activateModule(moduleID: RuntimeDeclaredToolbarUIModule.moduleID)
            XCTFail("Expected unsatisfiedRuntimeRequirement.")
        } catch {
            guard case let ModuleManagerError.unsatisfiedRuntimeRequirement(moduleID, reason) = error else {
                return XCTFail("Expected unsatisfiedRuntimeRequirement, received \(error).")
            }
            XCTAssertEqual(moduleID, RuntimeDeclaredToolbarUIModule.moduleID)
            XCTAssertTrue(reason.contains("toolbarItemID"))
        }
    }

    func testDeclaredUIContributionActivates() async throws {
        let manifest = RuntimeDeclaredToolbarUIModule.moduleManifest(declaredToolbarItemIDs: ["declared.toolbar.action"])
        let manager = try makeManager(
            manifests: [manifest],
            registrations: [
                RuntimeDeclaredToolbarUIModule.entryPoint: { RuntimeDeclaredToolbarUIModule(manifest: manifest) }
            ]
        )

        try await manager.activateModule(moduleID: RuntimeDeclaredToolbarUIModule.moduleID)

        XCTAssertEqual(manager.activeUIModuleID, RuntimeDeclaredToolbarUIModule.moduleID)
    }

    private func makeManager(
        manifests: [ModuleManifest],
        registrations: [String: ModuleFactory],
        services: any ForsettiServiceProviding = ForsettiServiceContainer()
    ) throws -> ModuleManager {
        let testBundle = try RuntimeTestBundle()
        for manifest in manifests {
            try testBundle.writeManifest(manifest, fileName: "\(manifest.moduleID).json")
        }

        let registry = ModuleRegistry()
        for (entryPoint, factory) in registrations {
            try registry.register(entryPoint: entryPoint, factory: factory)
        }

        let manager = ModuleManager(
            manifestLoader: ManifestLoader(),
            moduleRegistry: registry,
            compatibilityChecker: CompatibilityChecker(
                runtimePlatform: .macOS,
                forsettiVersion: ForsettiVersion.current,
                capabilityPolicy: AllowAllCapabilityPolicy()
            ),
            activationStore: SharedInMemoryActivationStore(),
            entitlementProvider: StaticEntitlementProvider(),
            uiSurfaceManager: UISurfaceManager(),
            context: ForsettiContext(
                eventBus: InMemoryEventBus(),
                services: services,
                logger: ConsoleForsettiLogger(),
                router: NoopOverlayRouter()
            )
        )

        _ = try manager.discoverModules(bundle: testBundle.bundle, subdirectory: "ForsettiManifests")
        return manager
    }
}

private final class RuntimeRequiredTelemetryModule: ForsettiModule {
    static let moduleID = "com.forsetti.tests.required-telemetry-service"
    static let entryPoint = "RuntimeRequiredTelemetryModule"
    static let moduleManifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: moduleID,
        displayName: "Required Telemetry Service",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        capabilitiesRequested: [.telemetry],
        entryPoint: entryPoint,
        runtimeRequirements: ModuleRuntimeRequirements(
            io: [
                ModuleIORequirement(
                    requirementID: "telemetry.required-service",
                    kind: .telemetry,
                    access: .emit,
                    required: true
                )
            ]
        )
    )

    let descriptor = runtimeServiceDescriptor(moduleID: moduleID, displayName: "Required Telemetry Service")
    let manifest = RuntimeRequiredTelemetryModule.moduleManifest

    func start(context _: any ForsettiModuleContext) throws {}
    func stop(context _: any ForsettiModuleContext) {}
}

private final class RuntimeSharedDatabaseConsumerModule: ForsettiModule {
    static let moduleID = "com.forsetti.tests.shared-database-consumer"
    static let entryPoint = "RuntimeSharedDatabaseConsumerModule"
    static let moduleManifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: moduleID,
        displayName: "Shared Database Consumer",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        capabilitiesRequested: [.sharedDatabase],
        entryPoint: entryPoint,
        runtimeRequirements: ModuleRuntimeRequirements(
            dataIsolation: ModuleDataIsolation(
                mode: .frameworkMediatedShared,
                requiredDefaultRoles: [.sharedDatabase]
            )
        )
    )

    let descriptor = runtimeServiceDescriptor(moduleID: moduleID, displayName: "Shared Database Consumer")
    let manifest = RuntimeSharedDatabaseConsumerModule.moduleManifest

    func start(context _: any ForsettiModuleContext) throws {}
    func stop(context _: any ForsettiModuleContext) {}
}

private final class RuntimeSharedDatabaseProviderModule: ForsettiModule {
    static let moduleID = "com.forsetti.tests.shared-database-provider"
    static let entryPoint = "RuntimeSharedDatabaseProviderModule"
    static let moduleManifest = ModuleManifest(
        schemaVersion: ModuleManifest.currentSchemaVersion,
        manifestTemplateVersion: .current,
        moduleID: moduleID,
        displayName: "Shared Database Provider",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service,
        supportedPlatforms: [.iOS, .macOS],
        minForsettiVersion: ForsettiVersion.current,
        capabilitiesRequested: [.sharedDatabase],
        entryPoint: entryPoint,
        defaultModuleRole: .sharedDatabase,
        runtimeRequirements: ModuleRuntimeRequirements()
    )

    let descriptor = runtimeServiceDescriptor(moduleID: moduleID, displayName: "Shared Database Provider")
    let manifest = RuntimeSharedDatabaseProviderModule.moduleManifest

    func start(context _: any ForsettiModuleContext) throws {}
    func stop(context _: any ForsettiModuleContext) {}
}

private final class RuntimeDeclaredToolbarUIModule: ForsettiUIModule {
    static let moduleID = "com.forsetti.tests.declared-toolbar-ui"
    static let entryPoint = "RuntimeDeclaredToolbarUIModule"

    static func moduleManifest(declaredToolbarItemIDs: [String]) -> ModuleManifest {
        ModuleManifest(
            schemaVersion: ModuleManifest.currentSchemaVersion,
            manifestTemplateVersion: .current,
            moduleID: moduleID,
            displayName: "Declared Toolbar UI",
            moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
            moduleType: .ui,
            supportedPlatforms: [.iOS, .macOS],
            minForsettiVersion: ForsettiVersion.current,
            capabilitiesRequested: [.toolbarItems],
            entryPoint: entryPoint,
            defaultModuleRole: .ui,
            runtimeRequirements: ModuleRuntimeRequirements(
                ui: ModuleUIRequirements(toolbarItemIDs: declaredToolbarItemIDs)
            )
        )
    }

    let descriptor = ModuleDescriptor(
        moduleID: moduleID,
        displayName: "Declared Toolbar UI",
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .ui
    )
    let manifest: ModuleManifest
    let uiContributions = UIContributions(
        toolbarItems: [
            ToolbarItemDescriptor(
                itemID: "declared.toolbar.action",
                title: "Declared Action",
                action: .publishEvent(type: "declared.toolbar.action", payload: nil)
            )
        ]
    )

    init(manifest: ModuleManifest) {
        self.manifest = manifest
    }

    func start(context _: any ForsettiModuleContext) throws {}
    func stop(context _: any ForsettiModuleContext) {}
}

private final class RuntimeRequirementTelemetryService: TelemetryService {
    func track(event: String, properties: [String: String]) {}
}

private func runtimeServiceDescriptor(moduleID: String, displayName: String) -> ModuleDescriptor {
    ModuleDescriptor(
        moduleID: moduleID,
        displayName: displayName,
        moduleVersion: SemVer(major: 1, minor: 0, patch: 0),
        moduleType: .service
    )
}
